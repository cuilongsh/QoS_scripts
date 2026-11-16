// SPDX-License-Identifier: GPL-2.0
/*
 * dvfs_hwp_msr.c - Kernel module to measure Intel Xeon HWP DVFS transition
 *                  latency directly in kernel space via native RDMSR/WRMSR
 *                  on MSR 0x774 (IA32_HWP_REQUEST) and MSR 0x198 (IA32_PERF_STATUS).
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/ktime.h>
#include <linux/delay.h>
#include <linux/slab.h>
#include <linux/sort.h>
#include <linux/smp.h>
#include <linux/cpumask.h>
#include <linux/topology.h>
#include <linux/sched.h>
#include <linux/kthread.h>
#include <linux/completion.h>
#include <asm/msr.h>
#include <asm/processor.h>

#define MSR_IA32_PERF_STATUS_REG    0x198
#define MSR_IA32_PM_ENABLE_REG      0x770
#define MSR_IA32_HWP_REQUEST_REG    0x774

static int cpu = 0;
module_param(cpu, int, 0444);
MODULE_PARM_DESC(cpu, "Target CPU core ID to run measurement on (default: 0)");

static int scaling_min_freq = 1200;
module_param(scaling_min_freq, int, 0444);
MODULE_PARM_DESC(scaling_min_freq, "HWP scaling_min_freq in MHz or kHz via MSR 0x774 (e.g. 1200 or 1200000, default: 1200)");

static int scaling_max_freq = 3200;
module_param(scaling_max_freq, int, 0444);
MODULE_PARM_DESC(scaling_max_freq, "HWP scaling_max_freq in MHz or kHz via MSR 0x774 (e.g. 3200 or 3200000, default: 3200)");

static int low_mhz = 0;
module_param(low_mhz, int, 0444);
MODULE_PARM_DESC(low_mhz, "Alias for scaling_min_freq in MHz (if > 0, overrides scaling_min_freq)");

static int high_mhz = 0;
module_param(high_mhz, int, 0444);
MODULE_PARM_DESC(high_mhz, "Alias for scaling_max_freq in MHz (if > 0, overrides scaling_max_freq)");

static char *hwp_mode = "lock";
module_param(hwp_mode, charp, 0444);
MODULE_PARM_DESC(hwp_mode, "HWP MSR 0x774 control mode: 'lock' (set min=max=target), 'max_only' (fix min=scaling_min_freq, toggle max), 'min_only' (fix max=scaling_max_freq, toggle min)");

static int iter = 100;
module_param(iter, int, 0444);
MODULE_PARM_DESC(iter, "Number of back-and-forth iterations (default: 100)");

static int delay_ms = 20;
module_param(delay_ms, int, 0444);
MODULE_PARM_DESC(delay_ms, "Settle delay between transitions in ms (default: 20)");

static int timeout_ms = 500;
module_param(timeout_ms, int, 0444);
MODULE_PARM_DESC(timeout_ms, "Timeout waiting for transition in ms (default: 500)");

static bool sync_siblings = true;
module_param(sync_siblings, bool, 0444);
MODULE_PARM_DESC(sync_siblings, "Also update HT sibling cores' 0x774 before polling on local core (default: true)");

static bool irq_disable = false;
module_param(irq_disable, bool, 0444);
MODULE_PARM_DESC(irq_disable, "Disable local IRQs during each transition poll (default: false)");

struct sample_rec {
	u64 trigger_ns;
	u64 first_change_ns;
	u64 target_reached_ns;
	u64 polls;
	u8 start_ratio;
	u8 first_ratio;
	u8 final_ratio;
	bool timed_out;
};

static inline u8 extract_ratio(u64 msr_val)
{
	return (u8)((msr_val >> 8) & 0xFF);
}

static inline u8 freq_to_ratio(int freq_val)
{
	/* Support both kHz (e.g., 1200000) and MHz (e.g., 1200) */
	if (freq_val >= 100000)
		return (u8)(freq_val / 100000);
	return (u8)(freq_val / 100);
}

static inline u64 build_hwp_req_minmax(u64 orig_hwp, u8 min_ratio, u8 max_ratio)
{
	/*
	 * IA32_HWP_REQUEST (0x774):
	 * Bits [7:0]   : Minimum_Performance (HWP scaling_min_freq ratio)
	 * Bits [15:8]  : Maximum_Performance (HWP scaling_max_freq ratio)
	 * Bits [23:16] : Desired_Performance (0 = autonomous within [min, max])
	 * Bit  [42]    : Package_Control (clear to use per-core control)
	 */
	u64 val = orig_hwp & ~(0xFFFFFFULL | (1ULL << 42));
	val |= ((u64)min_ratio) | ((u64)max_ratio << 8);
	return val;
}

static inline u64 build_hwp_req_for_target(u64 orig_hwp, u8 target_ratio,
					   u8 low_ratio, u8 high_ratio)
{
	u8 req_min = target_ratio;
	u8 req_max = target_ratio;

	if (hwp_mode && strcmp(hwp_mode, "max_only") == 0) {
		/* Keep HWP min fixed at scaling_min_freq, only toggle HWP max */
		req_min = low_ratio;
		req_max = target_ratio;
	} else if (hwp_mode && strcmp(hwp_mode, "min_only") == 0) {
		/* Keep HWP max fixed at scaling_max_freq, only toggle HWP min */
		req_min = target_ratio;
		req_max = high_ratio;
	}
	return build_hwp_req_minmax(orig_hwp, req_min, req_max);
}

/* Native inline RDMSR/WRMSR on the current CPU core */
static __always_inline u64 native_rdmsr64(u32 reg)
{
	u32 low, high;
	asm volatile("rdmsr" : "=a"(low), "=d"(high) : "c"(reg));
	return ((u64)high << 32) | low;
}

static __always_inline void native_wrmsr64(u32 reg, u64 val)
{
	u32 low = (u32)val;
	u32 high = (u32)(val >> 32);
	asm volatile("wrmsr" : : "c"(reg), "a"(low), "d"(high) : "memory");
}

static int cmp_u64(const void *a, const void *b)
{
	u64 va = *(const u64 *)a;
	u64 vb = *(const u64 *)b;
	return (va > vb) - (va < vb);
}

/* Linear interpolation percentile in nanoseconds (pct in [1..99]) */
static u64 get_percentile_ns(const u64 *sorted, int n, int pct)
{
	u64 idx_num, lo, hi, frac;

	if (n <= 0)
		return 0;
	if (n == 1)
		return sorted[0];

	idx_num = (u64)pct * (u64)(n - 1); /* scaled by 100 */
	lo = idx_num / 100;
	frac = idx_num % 100;
	hi = (frac == 0) ? lo : (lo + 1);
	if (hi >= (u64)n)
		hi = n - 1;

	return (sorted[lo] * (100 - frac) + sorted[hi] * frac) / 100;
}

static void print_percentile_table(const char *metric_name, const u64 *sorted, int n)
{
	static const int pcts[9] = {1, 10, 20, 30, 50, 70, 80, 90, 99};
	static const char * const labels[9] = {
		"P1 ", "P10", "P20", "P30", "P50", "P70", "P80", "P90", "P99"
	};
	static const char * const interval_names[9] = {
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
	u64 vals[9];
	int bucket_cnt[10] = {0};
	int i, j, cum = 0;

	for (i = 0; i < 9; i++)
		vals[i] = get_percentile_ns(sorted, n, pcts[i]);

	for (j = 0; j < n; j++) {
		u64 v = sorted[j];
		int b = 9;
		for (i = 0; i < 9; i++) {
			if (v <= vals[i]) {
				b = i;
				break;
			}
		}
		bucket_cnt[b]++;
	}

	pr_info("  [%s Percentiles & Interval Counts (Total=%d, min=%llu.%02llu us, max=%llu.%02llu us)]\n",
		metric_name, n,
		sorted[0] / 1000, (sorted[0] % 1000) / 10,
		sorted[n - 1] / 1000, (sorted[n - 1] % 1000) / 10);

	for (i = 0; i < 9; i++) {
		u64 low_b = (i == 0) ? sorted[0] : vals[i - 1];
		cum += bucket_cnt[i];
		pr_info("    %s : %6llu.%02llu us | Interval %s [%6llu.%02llu, %6llu.%02llu] us : %3d 次 | Cumulative (<= %s): %3d 次\n",
			labels[i],
			vals[i] / 1000, (vals[i] % 1000) / 10,
			interval_names[i],
			low_b / 1000, (low_b % 1000) / 10,
			vals[i] / 1000, (vals[i] % 1000) / 10,
			bucket_cnt[i], labels[i], cum);
	}
	if (bucket_cnt[9] > 0) {
		cum += bucket_cnt[9];
		pr_info("    Max : %6llu.%02llu us | Interval (P99, max] [%6llu.%02llu, %6llu.%02llu] us : %3d 次 | Cumulative (<= Max): %3d 次\n",
			sorted[n - 1] / 1000, (sorted[n - 1] % 1000) / 10,
			vals[8] / 1000, (vals[8] % 1000) / 10,
			sorted[n - 1] / 1000, (sorted[n - 1] % 1000) / 10,
			bucket_cnt[9], cum);
	}
}

static void print_stats(const char *label, struct sample_rec *samples, int count)
{
	u64 sum_trig = 0, sum_first = 0, sum_target = 0;
	u64 min_first = U64_MAX, max_first = 0;
	u64 min_target = U64_MAX, max_target = 0;
	int valid = 0, i;
	u64 *first_arr, *target_arr;
	u64 avg_trig, avg_first, avg_target;

	first_arr = kmalloc_array(count, sizeof(u64), GFP_KERNEL);
	target_arr = kmalloc_array(count, sizeof(u64), GFP_KERNEL);
	if (!first_arr || !target_arr) {
		kfree(first_arr);
		kfree(target_arr);
		return;
	}

	for (i = 0; i < count; i++) {
		if (samples[i].timed_out)
			continue;
		first_arr[valid] = samples[i].first_change_ns;
		target_arr[valid] = samples[i].target_reached_ns;
		valid++;

		sum_trig += samples[i].trigger_ns;
		sum_first += samples[i].first_change_ns;
		sum_target += samples[i].target_reached_ns;

		if (samples[i].first_change_ns < min_first)
			min_first = samples[i].first_change_ns;
		if (samples[i].first_change_ns > max_first)
			max_first = samples[i].first_change_ns;

		if (samples[i].target_reached_ns < min_target)
			min_target = samples[i].target_reached_ns;
		if (samples[i].target_reached_ns > max_target)
			max_target = samples[i].target_reached_ns;
	}

	pr_info("\n=== %s Summary (%d/%d valid transitions) ===\n", label, valid, count);
	if (valid == 0) {
		pr_info("  No valid transitions observed (all timed out)!\n");
		kfree(first_arr);
		kfree(target_arr);
		return;
	}

	avg_trig = sum_trig / valid;
	avg_first = sum_first / valid;
	avg_target = sum_target / valid;

	sort(first_arr, valid, sizeof(u64), cmp_u64, NULL);
	sort(target_arr, valid, sizeof(u64), cmp_u64, NULL);

	pr_info("  Trigger Write Cost      : avg = %5llu.%03llu us (%llu ns)\n",
		avg_trig / 1000, avg_trig % 1000, avg_trig);
	pr_info("  First MSR 0x198 Change  : avg = %6llu.%02llu us | min = %6llu.%02llu us | max = %6llu.%02llu us\n",
		avg_first / 1000, (avg_first % 1000) / 10,
		min_first / 1000, (min_first % 1000) / 10,
		max_first / 1000, (max_first % 1000) / 10);
	pr_info("  Target Ratio Reached    : avg = %6llu.%02llu us | min = %6llu.%02llu us | max = %6llu.%02llu us\n",
		avg_target / 1000, (avg_target % 1000) / 10,
		min_target / 1000, (min_target % 1000) / 10,
		max_target / 1000, (max_target % 1000) / 10);

	print_percentile_table("First MSR 0x198 Change (FirstChg)", first_arr, valid);
	print_percentile_table("Target Ratio Reached (TargetRch)", target_arr, valid);

	kfree(first_arr);
	kfree(target_arr);
}

static void run_one_transition(u64 orig_local_hwp, u8 target_ratio,
			       u8 low_ratio, u8 high_ratio,
			       const struct cpumask *sib_mask,
			       const u64 *orig_sib_hwp,
			       u64 timeout_ns, struct sample_rec *out)
{
	u64 msr_val, hwp_val;
	u64 t0, t_trig, t_first = 0, t_done = 0, now;
	u8 initial_ratio, first_ratio, cur_ratio;
	u64 polls = 0;
	bool timed_out = false;
	unsigned long flags = 0;
	int sib;

	/*
	 * Pre-configure any sibling hardware threads on the same physical core
	 * before starting the local core WRMSR -> RDMSR latency timer, so the
	 * sibling doesn't hold the physical core at a higher P-state, while
	 * keeping the measured critical path strictly local-core WRMSR(0x774) -> RDMSR(0x198).
	 */
	if (sync_siblings && sib_mask) {
		for_each_cpu(sib, sib_mask) {
			if (sib == smp_processor_id())
				continue;
			hwp_val = build_hwp_req_for_target(orig_sib_hwp[sib],
							   target_ratio,
							   low_ratio, high_ratio);
			wrmsrq_on_cpu(sib, MSR_IA32_HWP_REQUEST_REG, hwp_val);
		}
	}

	hwp_val = build_hwp_req_for_target(orig_local_hwp, target_ratio,
					   low_ratio, high_ratio);
	msr_val = native_rdmsr64(MSR_IA32_PERF_STATUS_REG);
	initial_ratio = extract_ratio(msr_val);
	first_ratio = initial_ratio;
	cur_ratio = initial_ratio;

	if (irq_disable)
		local_irq_save(flags);
	else
		preempt_disable();

	t0 = ktime_get_raw_ns();
	native_wrmsr64(MSR_IA32_HWP_REQUEST_REG, hwp_val);
	t_trig = ktime_get_raw_ns();

	while (1) {
		polls++;
		msr_val = native_rdmsr64(MSR_IA32_PERF_STATUS_REG);
		now = ktime_get_raw_ns();
		cur_ratio = extract_ratio(msr_val);

		if (t_first == 0 && cur_ratio != initial_ratio) {
			t_first = now;
			first_ratio = cur_ratio;
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
			if (t_first == 0)
				t_first = now;
			break;
		}
	}

	if (irq_disable)
		local_irq_restore(flags);
	else
		preempt_enable();

	out->trigger_ns = t_trig - t0;
	out->first_change_ns = t_first - t0;
	out->target_reached_ns = t_done - t0;
	out->polls = polls;
	out->start_ratio = initial_ratio;
	out->first_ratio = first_ratio;
	out->final_ratio = cur_ratio;
	out->timed_out = timed_out;
}

struct bench_ctx {
	struct completion done;
	int ret;
};

static int bench_thread_fn(void *data)
{
	struct bench_ctx *bctx = data;
	u8 low_ratio = freq_to_ratio(low_mhz > 0 ? low_mhz : scaling_min_freq);
	u8 high_ratio = freq_to_ratio(high_mhz > 0 ? high_mhz : scaling_max_freq);
	u64 pm_enable = 0, cur_status = 0, orig_local_hwp = 0;
	u64 *orig_sib_hwp = NULL;
	const struct cpumask *sib_mask;
	struct sample_rec *up_samples = NULL;
	struct sample_rec *down_samples = NULL;
	struct sample_rec warmup;
	u64 timeout_ns = (u64)timeout_ms * 1000000ULL;
	int sib, i;

	if (smp_processor_id() != cpu) {
		pr_err("dvfs_hwp_msr: thread not running on target CPU %d (on %d)\n",
		       cpu, smp_processor_id());
		bctx->ret = -EINVAL;
		goto out;
	}

	pm_enable = native_rdmsr64(MSR_IA32_PM_ENABLE_REG);
	if (!(pm_enable & 1)) {
		pr_err("dvfs_hwp_msr: HWP is not enabled on CPU %d (IA32_PM_ENABLE=0x%llx)\n",
		       cpu, pm_enable);
		bctx->ret = -ENOTSUPP;
		goto out;
	}

	cur_status = native_rdmsr64(MSR_IA32_PERF_STATUS_REG);
	orig_local_hwp = native_rdmsr64(MSR_IA32_HWP_REQUEST_REG);

	sib_mask = topology_sibling_cpumask(cpu);
	orig_sib_hwp = kcalloc(nr_cpu_ids, sizeof(u64), GFP_KERNEL);
	if (!orig_sib_hwp) {
		bctx->ret = -ENOMEM;
		goto out;
	}

	for_each_cpu(sib, sib_mask) {
		rdmsrq_on_cpu(sib, MSR_IA32_HWP_REQUEST_REG, &orig_sib_hwp[sib]);
	}

	up_samples = kcalloc(iter, sizeof(struct sample_rec), GFP_KERNEL);
	down_samples = kcalloc(iter, sizeof(struct sample_rec), GFP_KERNEL);
	if (!up_samples || !down_samples) {
		bctx->ret = -ENOMEM;
		goto out_free;
	}

	pr_info("================================================================================\n");
	pr_info("Intel Xeon Kernel-Space HWP DVFS Latency Benchmark (MSR 0x774 -> MSR 0x198)\n");
	pr_info("================================================================================\n");
	pr_info("Target CPU        : %d (Thread Siblings: %*pbl)\n",
		cpu, cpumask_pr_args(sib_mask));
	pr_info("HWP Enabled       : Yes (IA32_PM_ENABLE=0x%llx, orig 0x774=0x%llx [min=%llu, max=%llu])\n",
		pm_enable, orig_local_hwp,
		orig_local_hwp & 0xFF, (orig_local_hwp >> 8) & 0xFF);
	pr_info("Current 0x198     : 0x%016llx (Ratio: %u -> %u MHz)\n",
		cur_status, extract_ratio(cur_status), extract_ratio(cur_status) * 100);
	pr_info("scaling_min_freq  : %u MHz (%u kHz, HWP Ratio 0x%02x = %u)\n",
		low_ratio * 100, low_ratio * 100000, low_ratio, low_ratio);
	pr_info("scaling_max_freq  : %u MHz (%u kHz, HWP Ratio 0x%02x = %u)\n",
		high_ratio * 100, high_ratio * 100000, high_ratio, high_ratio);
	pr_info("HWP Control Mode  : %s (Low 0x774=0x%llx <-> High 0x774=0x%llx)\n",
		hwp_mode ? hwp_mode : "lock",
		build_hwp_req_for_target(orig_local_hwp, low_ratio, low_ratio, high_ratio),
		build_hwp_req_for_target(orig_local_hwp, high_ratio, low_ratio, high_ratio));
	pr_info("Iterations        : %d (Timeout: %d ms, Settle Delay: %d ms, irq_disable: %d)\n",
		iter, timeout_ms, delay_ms, irq_disable);
	pr_info("================================================================================\n");

	/* Warmup / initialize to scaling_min_freq */
	run_one_transition(orig_local_hwp, low_ratio, low_ratio, high_ratio,
			   sib_mask, orig_sib_hwp, timeout_ns, &warmup);
	msleep(delay_ms);

	pr_info("%-5s | %-9s | %-15s | %-12s | %-14s | %-14s | %-8s | %s\n",
		"Iter", "Direction", "Ratio (S->1->E)", "Trigger(ns)", "FirstChg(us)", "TargetRch(us)", "Polls", "Status");
	pr_info("------+-----------+-----------------+--------------+----------------+----------------+----------+-------\n");

	for (i = 0; i < iter; i++) {
		/* 1. Low -> High (scaling_min_freq -> scaling_max_freq) */
		run_one_transition(orig_local_hwp, high_ratio, low_ratio, high_ratio,
				   sib_mask, orig_sib_hwp, timeout_ns, &up_samples[i]);
		pr_info("%-5d | %-9s | %2u -> %2u -> %2u  | %9llu ns | %11llu.%02llu | %11llu.%02llu | %8llu | %s\n",
			i + 1, "Low->High",
			up_samples[i].start_ratio, up_samples[i].first_ratio, up_samples[i].final_ratio,
			up_samples[i].trigger_ns,
			up_samples[i].first_change_ns / 1000, (up_samples[i].first_change_ns % 1000) / 10,
			up_samples[i].target_reached_ns / 1000, (up_samples[i].target_reached_ns % 1000) / 10,
			up_samples[i].polls,
			up_samples[i].timed_out ? "TIMEOUT" : "OK");

		msleep(delay_ms);

		/* 2. High -> Low (scaling_max_freq -> scaling_min_freq) */
		run_one_transition(orig_local_hwp, low_ratio, low_ratio, high_ratio,
				   sib_mask, orig_sib_hwp, timeout_ns, &down_samples[i]);
		pr_info("%-5d | %-9s | %2u -> %2u -> %2u  | %9llu ns | %11llu.%02llu | %11llu.%02llu | %8llu | %s\n",
			i + 1, "High->Low",
			down_samples[i].start_ratio, down_samples[i].first_ratio, down_samples[i].final_ratio,
			down_samples[i].trigger_ns,
			down_samples[i].first_change_ns / 1000, (down_samples[i].first_change_ns % 1000) / 10,
			down_samples[i].target_reached_ns / 1000, (down_samples[i].target_reached_ns % 1000) / 10,
			down_samples[i].polls,
			down_samples[i].timed_out ? "TIMEOUT" : "OK");

		msleep(delay_ms);
	}

	print_stats("Up-scaling (Low -> High)", up_samples, iter);
	print_stats("Down-scaling (High -> Low)", down_samples, iter);

	/* Restore original HWP_REQUEST on target core and siblings */
	native_wrmsr64(MSR_IA32_HWP_REQUEST_REG, orig_local_hwp);
	for_each_cpu(sib, sib_mask) {
		if (sib == cpu)
			continue;
		wrmsrq_on_cpu(sib, MSR_IA32_HWP_REQUEST_REG, orig_sib_hwp[sib]);
	}

	bctx->ret = 0;

out_free:
	kfree(up_samples);
	kfree(down_samples);
	kfree(orig_sib_hwp);
out:
	complete(&bctx->done);
	return 0;
}

static int __init dvfs_hwp_msr_init(void)
{
	struct task_struct *task;
	struct bench_ctx bctx;
	u8 r_min = freq_to_ratio(low_mhz > 0 ? low_mhz : scaling_min_freq);
	u8 r_max = freq_to_ratio(high_mhz > 0 ? high_mhz : scaling_max_freq);

	if (!cpu_online(cpu)) {
		pr_err("dvfs_hwp_msr: CPU %d is not online\n", cpu);
		return -EINVAL;
	}

	if (r_min == 0 || r_max == 0 || r_min == r_max) {
		pr_err("dvfs_hwp_msr: invalid scaling_min_freq (%d -> ratio %u) or scaling_max_freq (%d -> ratio %u)\n",
		       scaling_min_freq, r_min, scaling_max_freq, r_max);
		return -EINVAL;
	}

	init_completion(&bctx.done);
	bctx.ret = 0;

	task = kthread_create_on_cpu(bench_thread_fn, &bctx, cpu, "dvfs_hwp_bench");
	if (IS_ERR(task)) {
		pr_err("dvfs_hwp_msr: failed to create kthread on CPU %d\n", cpu);
		return PTR_ERR(task);
	}

	wake_up_process(task);
	wait_for_completion(&bctx.done);

	return bctx.ret;
}

static void __exit dvfs_hwp_msr_exit(void)
{
	pr_info("dvfs_hwp_msr: module unloaded.\n");
}

module_init(dvfs_hwp_msr_init);
module_exit(dvfs_hwp_msr_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("QoS Benchmark");
MODULE_DESCRIPTION("Kernel-space Intel Xeon HWP DVFS transition latency benchmark via MSR 0x774 & 0x198");
