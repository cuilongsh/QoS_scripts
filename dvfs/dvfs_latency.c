#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sched.h>
#include <time.h>
#include <errno.h>
#include <getopt.h>
#include <math.h>

/* Intel MSR addresses */
#define MSR_IA32_PERF_STATUS    0x198
#define MSR_IA32_PERF_CTL       0x199
#define MSR_IA32_PM_ENABLE      0x770
#define MSR_IA32_HWP_CAPABILITIES 0x771
#define MSR_IA32_HWP_REQUEST    0x774

typedef enum {
    MODE_SYSFS = 0,     /* Write to scaling_setspeed or scaling_max/min_freq */
    MODE_HWP_MSR,       /* Write directly to MSR 0x774 (IA32_HWP_REQUEST) */
    MODE_PERF_CTL_MSR   /* Write directly to MSR 0x199 (IA32_PERF_CTL) */
} trigger_mode_t;

static inline uint64_t rdtsc_ordered(void) {
    uint32_t lo, hi;
    __asm__ __volatile__ (
        "lfence\n\t"
        "rdtsc\n\t"
        : "=a"(lo), "=d"(hi)
        :
        : "memory"
    );
    return ((uint64_t)hi << 32) | lo;
}

static inline uint64_t get_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static int pin_to_cpu(int cpu) {
    cpu_set_t mask;
    CPU_ZERO(&mask);
    CPU_SET(cpu, &mask);
    if (sched_setaffinity(0, sizeof(mask), &mask) < 0) {
        perror("sched_setaffinity");
        return -1;
    }
    return 0;
}

static int open_msr(int cpu, int flags) {
    char path[64];
    snprintf(path, sizeof(path), "/dev/cpu/%d/msr", cpu);
    int fd = open(path, flags);
    if (fd < 0) {
        fprintf(stderr, "Error opening %s: %s (Make sure running as root and 'modprobe msr' is loaded)\n",
                path, strerror(errno));
    }
    return fd;
}

static inline int read_msr(int fd, uint32_t reg, uint64_t *val) {
    if (pread(fd, val, sizeof(*val), reg) != sizeof(*val)) {
        return -1;
    }
    return 0;
}

static inline int write_msr(int fd, uint32_t reg, uint64_t val) {
    if (pwrite(fd, &val, sizeof(val), reg) != sizeof(val)) {
        return -1;
    }
    return 0;
}

/* Extract current operating ratio (100MHz multiplier on Xeon) from MSR 0x198 bits [15:8] */
static inline uint8_t get_perf_status_ratio(uint64_t msr_val) {
    return (uint8_t)((msr_val >> 8) & 0xFF);
}

/* Read sysfs sibling CPUs (e.g. "0,120") so we set freq on both HT siblings of a physical core */
static int get_thread_siblings(int cpu, int *siblings, int max_siblings) {
    char path[128], buf[128];
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/topology/thread_siblings_list", cpu);
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        siblings[0] = cpu;
        return 1;
    }
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) {
        siblings[0] = cpu;
        return 1;
    }
    buf[n] = '\0';

    int count = 0;
    char *saveptr = NULL;
    char *tok = strtok_r(buf, ",\n", &saveptr);
    while (tok && count < max_siblings) {
        int a, b;
        if (sscanf(tok, "%d-%d", &a, &b) == 2) {
            for (int c = a; c <= b && count < max_siblings; c++) {
                siblings[count++] = c;
            }
        } else if (sscanf(tok, "%d", &a) == 1) {
            siblings[count++] = a;
        }
        tok = strtok_r(NULL, ",\n", &saveptr);
    }
    if (count == 0) {
        siblings[0] = cpu;
        return 1;
    }
    return count;
}

typedef struct {
    int num_siblings;
    int siblings[8];
    int msr_fds[8];
    int sysfs_min_fds[8];
    int sysfs_max_fds[8];
    char orig_min[8][64];
    char orig_max[8][64];
    uint64_t orig_hwp[8];
    uint64_t orig_perf_ctl[8];
} core_ctx_t;

static int set_freq_sysfs(core_ctx_t *ctx, int ratio) {
    char buf[32];
    int freq_khz = ratio * 100000; /* 1 ratio unit = 100 MHz = 100,000 kHz */
    int len = snprintf(buf, sizeof(buf), "%d\n", freq_khz);

    for (int i = 0; i < ctx->num_siblings; i++) {
        int fd_min = ctx->sysfs_min_fds[i];
        int fd_max = ctx->sysfs_max_fds[i];
        /* Write min and max to lock target frequency */
        if (pwrite(fd_min, buf, len, 0) < 0) {
            /* If new min > old max, write max first then min */
            if (pwrite(fd_max, buf, len, 0) < 0) return -1;
            if (pwrite(fd_min, buf, len, 0) < 0) return -1;
        } else {
            if (pwrite(fd_max, buf, len, 0) < 0) return -1;
        }
    }
    return 0;
}

static int set_freq_hwp_msr(core_ctx_t *ctx, uint8_t ratio) {
    /*
     * IA32_HWP_REQUEST (0x774):
     * Bits [7:0]   : Minimum_Performance
     * Bits [15:8]  : Maximum_Performance
     * Bits [23:16] : Desired_Performance
     * Bit  [42]    : Package_Control (clear to use per-core control)
     */
    for (int i = 0; i < ctx->num_siblings; i++) {
        uint64_t val = ctx->orig_hwp[i] & ~(0xFFFFFFULL | (1ULL << 42));
        val |= ((uint64_t)ratio) | ((uint64_t)ratio << 8);
        if (write_msr(ctx->msr_fds[i], MSR_IA32_HWP_REQUEST, val) < 0) {
            return -1;
        }
    }
    return 0;
}

static int set_freq_perf_ctl_msr(core_ctx_t *ctx, uint8_t ratio) {
    /*
     * IA32_PERF_CTL (0x199):
     * Bits [15:8] : Target performance State Value
     */
    for (int i = 0; i < ctx->num_siblings; i++) {
        uint64_t val = (ctx->orig_perf_ctl[i] & ~0xFF00ULL) | ((uint64_t)ratio << 8);
        if (write_msr(ctx->msr_fds[i], MSR_IA32_PERF_CTL, val) < 0) {
            return -1;
        }
    }
    return 0;
}

static void usage(const char *prog) {
    printf("Usage: %s [options]\n"
           "Measure DVFS transition latency on Intel Xeon via MSR 0x198 (IA32_PERF_STATUS)\n\n"
           "Options:\n"
           "  -c, --cpu <cpu>        Target CPU core ID to pin and measure (default: 0)\n"
           "  -l, --low <mhz>        Low frequency in MHz, e.g. 1200 (default: 1200)\n"
           "  -H, --high <mhz>       High frequency in MHz, e.g. 3200 (default: 3200)\n"
           "  -i, --iter <num>       Number of back-and-forth iterations (default: 20)\n"
           "  -m, --mode <mode>      Trigger method: 'sysfs', 'hwp' (0x774), or 'perf_ctl' (0x199) (default: sysfs)\n"
           "  -t, --timeout <ms>     Timeout waiting for transition in ms (default: 500)\n"
           "  -d, --delay <ms>       Settle delay between transitions in ms (default: 50)\n"
           "  -f, --first-change     Measure latency to *first* ratio change instead of reaching exact target\n"
           "  -h, --help             Show this help message\n",
           prog);
}

typedef struct {
    double trigger_us;
    double first_change_us;
    double target_reached_us;
    uint64_t polls;
    uint8_t start_ratio;
    uint8_t first_ratio;
    uint8_t final_ratio;
    bool timed_out;
} sample_t;

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a;
    double db = *(const double *)b;
    return (da > db) - (da < db);
}

static double get_percentile(const double *sorted, int n, double p) {
    if (n <= 0) return 0.0;
    if (n == 1) return sorted[0];
    double idx = (p / 100.0) * (n - 1);
    int lo = (int)floor(idx);
    int hi = (int)ceil(idx);
    double frac = idx - lo;
    return sorted[lo] * (1.0 - frac) + sorted[hi] * frac;
}

static void print_percentile_chart(const char *metric_name, const double *sorted, int n) {
    static const double pcts[9] = {1.0, 10.0, 20.0, 30.0, 50.0, 70.0, 80.0, 90.0, 99.0};
    static const char *labels[9] = {"P1 ", "P10", "P20", "P30", "P50", "P70", "P80", "P90", "P99"};
    static const char *interval_names[9] = {
        "[min, P1 ]",
        "(P1 , P10]",
        "(P10, P20]",
        "(P20, P30]",
        "(P30, P50]",
        "(P50, P70]",
        "(P70, P80]",
        "(P80, P90]",
        "(P90, P99]"
    };
    double vals[9];

    for (int i = 0; i < 9; i++) {
        vals[i] = get_percentile(sorted, n, pcts[i]);
    }

    int bucket_cnt[10] = {0};
    for (int j = 0; j < n; j++) {
        double v = sorted[j];
        int b = 9;
        for (int i = 0; i < 9; i++) {
            if (v <= vals[i]) {
                b = i;
                break;
            }
        }
        bucket_cnt[b]++;
    }

    printf("\n  [%s Percentiles & Interval Counts (Total=%d, min=%.2f us, max=%.2f us)]\n",
           metric_name, n, sorted[0], sorted[n - 1]);
    int cum = 0;
    for (int i = 0; i < 9; i++) {
        cum += bucket_cnt[i];
        double low_b = (i == 0) ? sorted[0] : vals[i - 1];
        printf("    %s : %9.2f us  | Interval %s [%8.2f, %8.2f] us : %3d 次 | Cumulative (<= %s): %3d 次\n",
               labels[i], vals[i], interval_names[i],
               low_b, vals[i], bucket_cnt[i], labels[i], cum);
    }
    if (bucket_cnt[9] > 0) {
        cum += bucket_cnt[9];
        printf("    Max : %9.2f us  | Interval (P99, max] [%8.2f, %8.2f] us : %3d 次 | Cumulative (<= Max): %3d 次\n",
               sorted[n - 1], vals[8], sorted[n - 1], bucket_cnt[9], cum);
    }
}

static void print_stats(const char *label, sample_t *samples, int count) {
    double sum_trig = 0, sum_first = 0, sum_target = 0;
    double min_target = 1e18, max_target = 0;
    double min_first = 1e18, max_first = 0;
    int valid = 0;

    double *first_arr = malloc(count * sizeof(double));
    double *target_arr = malloc(count * sizeof(double));

    for (int i = 0; i < count; i++) {
        if (samples[i].timed_out) continue;
        first_arr[valid] = samples[i].first_change_us;
        target_arr[valid] = samples[i].target_reached_us;
        valid++;
        sum_trig += samples[i].trigger_us;
        sum_first += samples[i].first_change_us;
        sum_target += samples[i].target_reached_us;

        if (samples[i].first_change_us < min_first) min_first = samples[i].first_change_us;
        if (samples[i].first_change_us > max_first) max_first = samples[i].first_change_us;

        if (samples[i].target_reached_us < min_target) min_target = samples[i].target_reached_us;
        if (samples[i].target_reached_us > max_target) max_target = samples[i].target_reached_us;
    }

    printf("\n=== %s Summary (%d/%d valid transitions) ===\n", label, valid, count);
    if (valid == 0) {
        printf("  No valid transitions observed (all timed out)!\n");
        free(first_arr);
        free(target_arr);
        return;
    }

    double avg_trig = sum_trig / valid;
    double avg_first = sum_first / valid;
    double avg_target = sum_target / valid;

    double var_target = 0;
    for (int i = 0; i < count; i++) {
        if (samples[i].timed_out) continue;
        double diff = samples[i].target_reached_us - avg_target;
        var_target += diff * diff;
    }
    double std_target = sqrt(var_target / valid);

    qsort(first_arr, valid, sizeof(double), cmp_double);
    qsort(target_arr, valid, sizeof(double), cmp_double);

    printf("  Trigger Write Cost      : avg = %8.2f us\n", avg_trig);
    printf("  First MSR 0x198 Change  : avg = %8.2f us | min = %8.2f us | max = %8.2f us\n",
           avg_first, min_first, max_first);
    printf("  Target Ratio Reached    : avg = %8.2f us | min = %8.2f us | max = %8.2f us | std = %6.2f us\n",
           avg_target, min_target, max_target, std_target);

    print_percentile_chart("First MSR 0x198 Change (FirstChg)", first_arr, valid);
    print_percentile_chart("Target Ratio Reached (TargetRch)", target_arr, valid);

    free(first_arr);
    free(target_arr);
}

static int run_transition(int msr_fd, trigger_mode_t mode,
                          core_ctx_t *ctx,
                          uint8_t target_ratio, uint64_t timeout_ns,
                          bool stop_on_first_change, sample_t *out) {
    uint64_t msr_val = 0;
    if (read_msr(msr_fd, MSR_IA32_PERF_STATUS, &msr_val) < 0) {
        perror("pread MSR 0x198");
        return -1;
    }
    uint8_t initial_ratio = get_perf_status_ratio(msr_val);

    uint64_t t0 = get_ns();
    int ret = 0;
    if (mode == MODE_SYSFS) {
        ret = set_freq_sysfs(ctx, target_ratio);
    } else if (mode == MODE_HWP_MSR) {
        ret = set_freq_hwp_msr(ctx, target_ratio);
    } else {
        ret = set_freq_perf_ctl_msr(ctx, target_ratio);
    }
    uint64_t t_trig = get_ns();

    if (ret < 0) {
        perror("Failed to trigger frequency change");
        return -1;
    }

    uint64_t t_first = 0;
    uint64_t t_done = 0;
    uint8_t first_ratio = initial_ratio;
    uint8_t cur_ratio = initial_ratio;
    uint64_t polls = 0;
    bool timed_out = false;

    while (1) {
        polls++;
        if (read_msr(msr_fd, MSR_IA32_PERF_STATUS, &msr_val) < 0) {
            perror("pread MSR 0x198 in poll");
            return -1;
        }
        uint64_t now = get_ns();
        cur_ratio = get_perf_status_ratio(msr_val);

        if (t_first == 0 && cur_ratio != initial_ratio) {
            t_first = now;
            first_ratio = cur_ratio;
            if (stop_on_first_change) {
                t_done = now;
                break;
            }
        }

        if (cur_ratio == target_ratio) {
            if (t_first == 0) {
                t_first = now;
                first_ratio = cur_ratio;
            }
            t_done = now;
            break;
        }

        if ((now - t0) > timeout_ns) {
            timed_out = true;
            t_done = now;
            if (t_first == 0) t_first = now;
            break;
        }
    }

    out->trigger_us = (double)(t_trig - t0) / 1000.0;
    out->first_change_us = (double)(t_first - t0) / 1000.0;
    out->target_reached_us = (double)(t_done - t0) / 1000.0;
    out->polls = polls;
    out->start_ratio = initial_ratio;
    out->first_ratio = first_ratio;
    out->final_ratio = cur_ratio;
    out->timed_out = timed_out;

    return 0;
}

int main(int argc, char **argv) {
    int cpu = 0;
    int low_mhz = 1200;
    int high_mhz = 3200;
    int iterations = 20;
    int timeout_ms = 500;
    int delay_ms = 50;
    bool stop_on_first = false;
    trigger_mode_t mode = MODE_SYSFS;

    static struct option long_opts[] = {
        {"cpu",          required_argument, 0, 'c'},
        {"low",          required_argument, 0, 'l'},
        {"high",         required_argument, 0, 'H'},
        {"iter",         required_argument, 0, 'i'},
        {"mode",         required_argument, 0, 'm'},
        {"timeout",      required_argument, 0, 't'},
        {"delay",        required_argument, 0, 'd'},
        {"first-change", no_argument,       0, 'f'},
        {"help",         no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "c:l:H:i:m:t:d:fh", long_opts, NULL)) != -1) {
        switch (opt) {
            case 'c': cpu = atoi(optarg); break;
            case 'l': low_mhz = atoi(optarg); break;
            case 'H': high_mhz = atoi(optarg); break;
            case 'i': iterations = atoi(optarg); break;
            case 't': timeout_ms = atoi(optarg); break;
            case 'd': delay_ms = atoi(optarg); break;
            case 'f': stop_on_first = true; break;
            case 'm':
                if (strcmp(optarg, "sysfs") == 0) mode = MODE_SYSFS;
                else if (strcmp(optarg, "hwp") == 0) mode = MODE_HWP_MSR;
                else if (strcmp(optarg, "perf_ctl") == 0) mode = MODE_PERF_CTL_MSR;
                else {
                    fprintf(stderr, "Unknown mode: %s\n", optarg);
                    usage(argv[0]);
                    return 1;
                }
                break;
            case 'h':
            default:
                usage(argv[0]);
                return (opt == 'h') ? 0 : 1;
        }
    }

    uint8_t low_ratio = (uint8_t)(low_mhz / 100);
    uint8_t high_ratio = (uint8_t)(high_mhz / 100);

    if (low_ratio == high_ratio) {
        fprintf(stderr, "Error: low_mhz (%d) and high_mhz (%d) map to the same ratio (%u).\n",
                low_mhz, high_mhz, low_ratio);
        return 1;
    }

    if (pin_to_cpu(cpu) < 0) {
        return 1;
    }

    core_ctx_t ctx;
    memset(&ctx, 0, sizeof(ctx));
    for (int i = 0; i < 8; i++) {
        ctx.msr_fds[i] = -1;
        ctx.sysfs_min_fds[i] = -1;
        ctx.sysfs_max_fds[i] = -1;
    }
    ctx.num_siblings = get_thread_siblings(cpu, ctx.siblings, 8);

    int msr_fd = open_msr(cpu, (mode == MODE_SYSFS) ? O_RDONLY : O_RDWR);
    if (msr_fd < 0) {
        return 1;
    }

    uint64_t cur_status = 0, pm_enable = 0;
    if (read_msr(msr_fd, MSR_IA32_PERF_STATUS, &cur_status) < 0) {
        perror("Failed to read MSR 0x198 (IA32_PERF_STATUS)");
        close(msr_fd);
        return 1;
    }

    bool hwp_enabled = (read_msr(msr_fd, MSR_IA32_PM_ENABLE, &pm_enable) == 0) && (pm_enable & 1);

    for (int i = 0; i < ctx.num_siblings; i++) {
        int sib = ctx.siblings[i];
        ctx.msr_fds[i] = open_msr(sib, (mode == MODE_SYSFS) ? O_RDONLY : O_RDWR);
        if (ctx.msr_fds[i] < 0) {
            close(msr_fd);
            return 1;
        }
        if (hwp_enabled) {
            read_msr(ctx.msr_fds[i], MSR_IA32_HWP_REQUEST, &ctx.orig_hwp[i]);
        }
        read_msr(ctx.msr_fds[i], MSR_IA32_PERF_CTL, &ctx.orig_perf_ctl[i]);

        if (mode == MODE_SYSFS) {
            char path_min[128], path_max[128];
            snprintf(path_min, sizeof(path_min), "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_min_freq", sib);
            snprintf(path_max, sizeof(path_max), "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_max_freq", sib);

            ctx.sysfs_min_fds[i] = open(path_min, O_RDWR);
            ctx.sysfs_max_fds[i] = open(path_max, O_RDWR);
            if (ctx.sysfs_min_fds[i] < 0 || ctx.sysfs_max_fds[i] < 0) {
                fprintf(stderr, "Error opening cpufreq sysfs files for CPU %d: %s\n", sib, strerror(errno));
                close(msr_fd);
                return 1;
            }
            if (pread(ctx.sysfs_min_fds[i], ctx.orig_min[i], sizeof(ctx.orig_min[i]) - 1, 0) < 0 ||
                pread(ctx.sysfs_max_fds[i], ctx.orig_max[i], sizeof(ctx.orig_max[i]) - 1, 0) < 0) {
                perror("Failed reading initial sysfs freq");
            }
        }
    }

    printf("================================================================================\n");
    printf("Intel Xeon DVFS Latency Benchmark (observing MSR 0x198 IA32_PERF_STATUS)\n");
    printf("================================================================================\n");
    printf("Target CPU        : %d (Core Thread Siblings: ", cpu);
    for (int i = 0; i < ctx.num_siblings; i++) {
        printf("%d%s", ctx.siblings[i], (i + 1 < ctx.num_siblings) ? "," : ")\n");
    }
    printf("HWP Enabled       : %s\n", hwp_enabled ? "Yes (IA32_PM_ENABLE=1)" : "No");
    printf("Trigger Mode      : %s\n", mode == MODE_SYSFS ? "sysfs (scaling_min/max_freq)" :
                                       (mode == MODE_HWP_MSR ? "Direct MSR 0x774 (IA32_HWP_REQUEST)" :
                                                               "Direct MSR 0x199 (IA32_PERF_CTL)"));
    printf("Current 0x198     : 0x%016lx (Ratio: %u -> %u MHz)\n",
           (unsigned long)cur_status, get_perf_status_ratio(cur_status),
           get_perf_status_ratio(cur_status) * 100);
    printf("Test Frequencies  : Low = %u MHz (Ratio %u) <-> High = %u MHz (Ratio %u)\n",
           low_ratio * 100, low_ratio, high_ratio * 100, high_ratio);
    printf("Iterations        : %d (Timeout: %d ms, Settle Delay: %d ms)\n",
           iterations, timeout_ms, delay_ms);
    printf("================================================================================\n\n");

    sample_t *up_samples = calloc(iterations, sizeof(sample_t));
    sample_t *down_samples = calloc(iterations, sizeof(sample_t));
    if (!up_samples || !down_samples) {
        perror("calloc");
        return 1;
    }

    uint64_t timeout_ns = (uint64_t)timeout_ms * 1000000ULL;

    /* Initialize to low frequency before starting */
    sample_t warmup;
    printf("Initializing CPU %d to Low Frequency (%u MHz)...\n", cpu, low_ratio * 100);
    run_transition(msr_fd, mode, &ctx, low_ratio, timeout_ns, false, &warmup);
    usleep(delay_ms * 1000);

    printf("\n%-5s | %-9s | %-15s | %-12s | %-14s | %-14s | %-8s | %s\n",
           "Iter", "Direction", "Ratio (S->1->E)", "Trigger(us)", "FirstChg(us)", "TargetRch(us)", "Polls", "Status");
    printf("------+-----------+-----------------+--------------+----------------+----------------+----------+-------\n");

    for (int i = 0; i < iterations; i++) {
        /* 1. Low -> High transition */
        if (run_transition(msr_fd, mode, &ctx, high_ratio, timeout_ns, stop_on_first, &up_samples[i]) < 0) {
            break;
        }
        printf("%-5d | %-9s | %2u -> %2u -> %2u  | %12.2f | %14.2f | %14.2f | %8lu | %s\n",
               i + 1, "Low->High",
               up_samples[i].start_ratio, up_samples[i].first_ratio, up_samples[i].final_ratio,
               up_samples[i].trigger_us, up_samples[i].first_change_us, up_samples[i].target_reached_us,
               (unsigned long)up_samples[i].polls,
               up_samples[i].timed_out ? "TIMEOUT" : "OK");

        usleep(delay_ms * 1000);

        /* 2. High -> Low transition */
        if (run_transition(msr_fd, mode, &ctx, low_ratio, timeout_ns, stop_on_first, &down_samples[i]) < 0) {
            break;
        }
        printf("%-5d | %-9s | %2u -> %2u -> %2u  | %12.2f | %14.2f | %14.2f | %8lu | %s\n",
               i + 1, "High->Low",
               down_samples[i].start_ratio, down_samples[i].first_ratio, down_samples[i].final_ratio,
               down_samples[i].trigger_us, down_samples[i].first_change_us, down_samples[i].target_reached_us,
               (unsigned long)down_samples[i].polls,
               down_samples[i].timed_out ? "TIMEOUT" : "OK");

        usleep(delay_ms * 1000);
    }

    print_stats("Up-scaling (Low -> High)", up_samples, iterations);
    print_stats("Down-scaling (High -> Low)", down_samples, iterations);

    /* Restore original settings */
    for (int i = 0; i < ctx.num_siblings; i++) {
        if (mode == MODE_SYSFS && ctx.sysfs_min_fds[i] >= 0 && ctx.sysfs_max_fds[i] >= 0) {
            if (ctx.orig_max[i][0]) pwrite(ctx.sysfs_max_fds[i], ctx.orig_max[i], strlen(ctx.orig_max[i]), 0);
            if (ctx.orig_min[i][0]) pwrite(ctx.sysfs_min_fds[i], ctx.orig_min[i], strlen(ctx.orig_min[i]), 0);
            if (ctx.orig_max[i][0]) pwrite(ctx.sysfs_max_fds[i], ctx.orig_max[i], strlen(ctx.orig_max[i]), 0);
            close(ctx.sysfs_min_fds[i]);
            close(ctx.sysfs_max_fds[i]);
        } else if (mode == MODE_HWP_MSR && hwp_enabled) {
            write_msr(ctx.msr_fds[i], MSR_IA32_HWP_REQUEST, ctx.orig_hwp[i]);
        } else if (mode == MODE_PERF_CTL_MSR) {
            write_msr(ctx.msr_fds[i], MSR_IA32_PERF_CTL, ctx.orig_perf_ctl[i]);
        }
        if (ctx.msr_fds[i] >= 0) close(ctx.msr_fds[i]);
    }

    free(up_samples);
    free(down_samples);
    close(msr_fd);
    return 0;
}
