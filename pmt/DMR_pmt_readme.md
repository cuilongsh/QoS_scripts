# DMR (Diamond Rapids) PMT Telemetry

Source: [intel/Intel-PMT](https://github.com/intel/Intel-PMT) — `xml/pmt.xml` and `xml/DMR/OOBMSM/*`.

Each DMR telemetry directory contains `dmr_aggregator.xml`, `dmr_aggregator_interface.xml`
and `dmr_common.xml`, which define the sample layout and transformation rules.

## DMR telemetry GUIDs

| GUID | Size (bytes) | Type | XML directory |
|---|---|---|---|
| 0x14151486 | 3104 | Core Performance | `DMR/OOBMSM/CORE-PERF` |
| 0x14302515 | 10656 | Core Environmental | `DMR/OOBMSM/CORE-ENV` |
| 0x1415910a | 8216 | Core RMID Performance | `DMR/OOBMSM/RMID-PERF` |
| 0x47903099 | 4120 | Core RMID Energy | `DMR/OOBMSM/RMID-ENERGY` |
| 0x13704937 | 3952 | D2D ULA and IO-CA | `DMR/OOBMSM/D2D-IO-CA` |
| 0x13693726 | 176 | QAT Accelerator | `DMR/OOBMSM/QAT` |
| 0x47324885 | 104 | SoC Topology | `DMR/OOBMSM/TOPO` |

## Verification on the test system

System: CPU family 19 (0x13), model 1, stepping 2, 1 socket, kernel 7.3.0-rc1.

```sh
for d in /sys/class/intel_pmt/telem*; do
  echo "$d guid=$(cat $d/guid) size=$(cat $d/size) dev=$(readlink -f $d/device | xargs basename)"
done
```

All 7 DMR GUIDs are present and the sizes match the repo. There are two `intel_vsec`
telemetry instances (`intel_vsec.telemetry.2` and `intel_vsec.telemetry.5`).

| GUID | Type | telem devices |
|---|---|---|
| 0x14151486 | CORE-PERF | telem6, telem10, telem19, telem23 |
| 0x14302515 | CORE-ENV | telem5, telem9, telem18, telem22 |
| 0x1415910a | RMID-PERF | telem7, telem11, telem20, telem24 |
| 0x47903099 | RMID-ENERGY | telem8, telem12, telem21, telem25 |
| 0x13704937 | D2D-IO-CA | telem4, telem17 |
| 0x13693726 | QAT | telem3, telem16 |
| 0x47324885 | TOPO | telem2, telem15 |
| 0x3074003 | *not in pmt.xml* (12288 bytes) | telem13, telem26 |
| 0x13274820 | *not in pmt.xml* (8192 bytes) | telem1, telem14 |

The telemN numbering depends on probe order and may differ between boots or systems.
Always locate devices by GUID:

```sh
grep -r 0x14151486 /sys/class/intel_pmt/telem*/guid
```

### Raw dump: CORE-PERF (telem10)

```sh
xxd -e -s 0 -l 64 -g8 -c8 /sys/class/intel_pmt/telem10/telem
```

Decoded with `CORE-PERF/dmr_aggregator.xml`, read twice 1 second apart:

```
0x0000 MOD_0_C0_RMID                                 0  Δ1s=0
0x0008 MOD_0_C0_UNHALTED_REF_CYCLES     52378856471890  Δ1s=57548062
0x0010 MOD_0_C0_UNHALTED_CORE_CYCLES    73344210170019  Δ1s=81986489
0x0018 MOD_0_C0_INST_RETIRED           209312978146921  Δ1s=129716962
0x0020 MOD_0_C0_PCNT                    73121123519600  Δ1s=81353954
0x0028 MOD_0_C0_CYCLE_ENERGY_COST     8063267409769792  Δ1s=5007091136
0x0030 MOD_0_C1_RMID                                 0  Δ1s=0
```

The counters increase between reads, so the layout matches and the data is live.
Each core uses 6 qwords (48 bytes): RMID, UNHALTED_REF_CYCLES, UNHALTED_CORE_CYCLES,
INST_RETIRED, PCNT, CYCLE_ENERGY_COST.

### Raw dump: TOPO (telem2)

```sh
xxd -e -s 0 -l 104 -g8 -c8 /sys/class/intel_pmt/telem2/telem
```

Decoded fields:

```
0x0000 CPUID_STEPPING=2 CPUID_MODEL=1 CPUID_FAMILY=0xF CPUID_EXT_FAMILY=4  (=> family 0x13)
       MINOR_STEPPING_ID=1
0x0008 IMH_0_EID=18 IMH_1_EID=19 CORES_PER_MODULE=2 CURR_SOCKET_ID=0
       IMH_DOMAIN_ID=8 CBB_0_DOMAIN_ID=255 CBB_1_DOMAIN_ID=1
```

The CPUID values match `lscpu`.

### QAT (telem3)

Reads all zeros, probably because QAT isn't in use.

## Cross-check with Intel-PMT `pmt.py`

```sh
cd /home/longcui/Intel-PMT/tools/collectd-agent
python pmt.py -s /home/longcui/Intel-PMT/xml/pmt.xml
```

`pmt.py` runs continuously (prints a full sample every ~5 s, ~7700 metrics per instance),
so stop it with Ctrl-C or wrap it with `timeout`. Output is Graphite format:
`pmt.<hostname>.<idx>.<sample_group>.<sample> <value> <timestamp>`.

`<idx>` is **not** the telemN number. It is the Nth endpoint with the same GUID, in telemN
order. The output name does not include the GUID, so different GUIDs share the same `<idx>`:

| idx | TOPO | QAT | D2D-IO-CA | CORE-ENV | CORE-PERF | RMID-PERF | RMID-ENERGY |
|---|---|---|---|---|---|---|---|
| 0 | telem2 | telem3 | telem4 | telem5 | telem6 | telem7 | telem8 |
| 1 | telem15 | telem16 | telem17 | telem9 | telem10 | telem11 | telem12 |
| 2 | - | - | - | telem18 | telem19 | telem20 | telem21 |
| 3 | - | - | - | telem22 | telem23 | telem24 | telem25 |

### Comparison results

| Item | Manual check (sysfs + xxd + XML) | `pmt.py` | Result |
|---|---|---|---|
| Endpoints found | 26 telem devices | 26 endpoints | Match |
| Decodable DMR GUIDs | 7 | 7 ("will decode ... with specification of ...") | Match |
| `0x13274820`, `0x3074003` | Not in pmt.xml | `ERROR ... does not understand PMT endpoint` | Match (both skip them) |
| TOPO telem2 | FAMILY=15, EXT_FAMILY=4, MODEL=1, STEPPING=2, MINOR_STEPPING=1, IMH_0/1_EID=18/19, CORES_PER_MODULE=2, IMH_DOMAIN_ID=8, CBB_0/1_DOMAIN_ID=255/1 | idx 0: same values | Match |
| TOPO telem15 | (not dumped earlier) | idx 1: IMH_DOMAIN_ID=9, CBB_1_DOMAIN_ID=3, rest same | Second IMH |
| CORE-PERF telem10 `MOD_0_C0_INST_RETIRED` | 209321168493480 | idx 1: 209320292340043 (a few seconds earlier) | Match (same counter, increasing) |
| CORE-PERF telem23 `MOD_0_C0_INST_RETIRED` | 142992900630233 | idx 3: 142992622616118 | Match |

`pmt.py` also applies the XML transformations, so it reports derived metrics that raw `xxd`
does not show, for example `mod_0_c0_freq_hist_r*` from CORE-ENV.

### Observation: paired endpoints per vsec instance

Each `intel_vsec.telemetry.*` device exposes CORE-ENV, CORE-PERF, RMID-PERF and RMID-ENERGY
twice. Non-zero qword counts:

| GUID | 1st copy | 2nd copy |
|---|---|---|
| CORE-ENV (1332 qwords) | telem5: 0, telem18: 0 | telem9: 541, telem22: 549 |
| CORE-PERF (388 qwords) | telem6: 64, telem19: 64 | telem10: 194, telem23: 194 |

The first copy has no core data (CORE-ENV all zero; CORE-PERF `MOD_0_C0_*` = 0), and the
active cores are in the second copy. TOPO reports `CBB_0_DOMAIN_ID=255` (probably unpopulated)
and `CBB_1_DOMAIN_ID=1`/`3`. So the first copy is likely an empty CBB slot. This is an
inference from the data and should be confirmed against the DMR spec.
In `pmt.py` output, the useful core data is therefore under idx **1** and **3**, not 0 and 2.

## Full telemetry list on this system

Two OOBMSM PCI functions each expose 13 telemetry endpoints:
`0000:00:02.1` (`intel_vsec.telemetry.2`, telem1–13) and
`0001:00:02.1` (`intel_vsec.telemetry.5`, telem14–26).
"Non-zero" is the number of non-zero 64-bit qwords at the time of the check.

| telem | PCI / vsec | GUID | Size | Type | pmt.py idx | Non-zero qwords | Status |
|---|---|---|---|---|---|---|---|
| telem1 | 0000:00:02.1 / telemetry.2 | 0x13274820 | 8192 | Unknown (not in pmt.xml) | - | 66/1024 | Not decodable |
| telem2 | 0000:00:02.1 / telemetry.2 | 0x47324885 | 104 | TOPO | 0 | 7/13 | Active (IMH_DOMAIN_ID=8) |
| telem3 | 0000:00:02.1 / telemetry.2 | 0x13693726 | 176 | QAT | 0 | 0/22 | All zero |
| telem4 | 0000:00:02.1 / telemetry.2 | 0x13704937 | 3952 | D2D-IO-CA | 0 | 53/494 | Active |
| telem5 | 0000:00:02.1 / telemetry.2 | 0x14302515 | 10656 | CORE-ENV | 0 | 0/1332 | All zero (empty CBB slot?) |
| telem6 | 0000:00:02.1 / telemetry.2 | 0x14151486 | 3104 | CORE-PERF | 0 | 64/388 | No core data (empty CBB slot?) |
| telem7 | 0000:00:02.1 / telemetry.2 | 0x1415910a | 8216 | RMID-PERF | 0 | 1024/1027 | Active |
| telem8 | 0000:00:02.1 / telemetry.2 | 0x47903099 | 4120 | RMID-ENERGY | 0 | 512/515 | Active |
| telem9 | 0000:00:02.1 / telemetry.2 | 0x14302515 | 10656 | CORE-ENV | 1 | 541/1332 | Active |
| telem10 | 0000:00:02.1 / telemetry.2 | 0x14151486 | 3104 | CORE-PERF | 1 | 194/388 | Active |
| telem11 | 0000:00:02.1 / telemetry.2 | 0x1415910a | 8216 | RMID-PERF | 1 | 1025/1027 | Active |
| telem12 | 0000:00:02.1 / telemetry.2 | 0x47903099 | 4120 | RMID-ENERGY | 1 | 513/515 | Active |
| telem13 | 0000:00:02.1 / telemetry.2 | 0x3074003 | 12288 | Unknown (not in pmt.xml) | - | 91/1536 | Not decodable |
| telem14 | 0001:00:02.1 / telemetry.5 | 0x13274820 | 8192 | Unknown (not in pmt.xml) | - | 47/1024 | Not decodable |
| telem15 | 0001:00:02.1 / telemetry.5 | 0x47324885 | 104 | TOPO | 1 | 7/13 | Active (IMH_DOMAIN_ID=9) |
| telem16 | 0001:00:02.1 / telemetry.5 | 0x13693726 | 176 | QAT | 1 | 0/22 | All zero |
| telem17 | 0001:00:02.1 / telemetry.5 | 0x13704937 | 3952 | D2D-IO-CA | 1 | 54/494 | Active |
| telem18 | 0001:00:02.1 / telemetry.5 | 0x14302515 | 10656 | CORE-ENV | 2 | 0/1332 | All zero (empty CBB slot?) |
| telem19 | 0001:00:02.1 / telemetry.5 | 0x14151486 | 3104 | CORE-PERF | 2 | 64/388 | No core data (empty CBB slot?) |
| telem20 | 0001:00:02.1 / telemetry.5 | 0x1415910a | 8216 | RMID-PERF | 2 | 1024/1027 | Active |
| telem21 | 0001:00:02.1 / telemetry.5 | 0x47903099 | 4120 | RMID-ENERGY | 2 | 512/515 | Active |
| telem22 | 0001:00:02.1 / telemetry.5 | 0x14302515 | 10656 | CORE-ENV | 3 | 549/1332 | Active |
| telem23 | 0001:00:02.1 / telemetry.5 | 0x14151486 | 3104 | CORE-PERF | 3 | 194/388 | Active |
| telem24 | 0001:00:02.1 / telemetry.5 | 0x1415910a | 8216 | RMID-PERF | 3 | 1025/1027 | Active |
| telem25 | 0001:00:02.1 / telemetry.5 | 0x47903099 | 4120 | RMID-ENERGY | 3 | 513/515 | Active |
| telem26 | 0001:00:02.1 / telemetry.5 | 0x3074003 | 12288 | Unknown (not in pmt.xml) | - | 94/1536 | Not decodable |

### Summary by type

| Type | GUID | 0000:00:02.1 | 0001:00:02.1 | Data status |
|---|---|---|---|---|
| TOPO (SoC topology) | 0x47324885 | telem2 | telem15 | Has data |
| QAT (accelerator) | 0x13693726 | telem3 | telem16 | All zero |
| D2D-IO-CA (die-to-die and IO caching agent) | 0x13704937 | telem4 | telem17 | Has data |
| CORE-ENV (core environmental) | 0x14302515 | telem5, telem9 | telem18, telem22 | telem5/18 all zero; telem9/22 have data |
| CORE-PERF (core performance) | 0x14151486 | telem6, telem10 | telem19, telem23 | telem6/19 no core data; telem10/23 have data |
| RMID-PERF | 0x1415910a | telem7, telem11 | telem20, telem24 | All have data |
| RMID-ENERGY | 0x47903099 | telem8, telem12 | telem21, telem25 | All have data |
| Unknown (not in pmt.xml) | 0x13274820 | telem1 | telem14 | Has data, not decodable |
| Unknown (not in pmt.xml) | 0x3074003 | telem13 | telem26 | Has data, not decodable |

Totals: TOPO x2, QAT x2, D2D-IO-CA x2, CORE-ENV x4, CORE-PERF x4, RMID-PERF x4,
RMID-ENERGY x4, unknown x4 (0x13274820 x2, 0x3074003 x2).

For RMID-PERF and RMID-ENERGY, both copies are non-zero, so the "empty CBB slot" pattern
seen in CORE-ENV/CORE-PERF can't be confirmed for them from raw data alone.

## Contents of each telemetry type (from DMR XML)

All samples are `Snapshot` type. Counts exclude `RESERVED_*` fields. `N` = index.

| Type | GUID | Samples | Main contents |
|---|---|---|---|
| TOPO | 0x47324885 | 720 | CPUID (stepping/model/family), IMH_N_EID, CBB_N_DOMAIN_ID, CORES_PER_MODULE, per-core enable bitmap `CBB_N_CN_EN` (x256), `CBB_N_AGG/WATCH/CRASH_N_ASSOC`, `DDR_MEM_N_EN` (x32), `IO_CA_N_EN` (x32) |
| CORE-PERF | 0x14151486 | 451 | Per core (64 cores = `MOD_N_CN`): RMID, UNHALTED_REF_CYCLES, UNHALTED_CORE_CYCLES, INST_RETIRED, PCNT, CYCLE_ENERGY_COST, EN; plus AGG_DATA_LOSS_COUNT/TIMESTAMP, LAST_UPDATE_TIMESTAMP |
| CORE-ENV | 0x14302515 | 2819 | Per core: FREQ, VOLT, TEMP, FREQ/VOLT/TEMP histograms (12 bins each), AGING_FREQ, AGING_VOLT, AGING_VOLT_COMP, USAGE_METER, EN; plus data-loss / last-update timestamps |
| RMID-PERF | 0x1415910a | 2051 | Per RMID (256): UNHALTED_REF_CYCLES, UNHALTED_CORE_CYCLES, INST_RETIRED, PCNT, each with a `_VALID` flag; plus data-loss / last-update timestamps |
| RMID-ENERGY | 0x47903099 | 1027 | Per RMID (256): CORE_ENERGY, ACTIVITY, each with a `_VALID` flag; plus data-loss / last-update timestamps |
| D2D-IO-CA | 0x13704937 | 521 | IO caching agent per-RMID RDT counters (MBM_TOTAL, MBM_MISS, CMT; x128 each), IO_CA_N_EN; UFI/UBR die-to-die port bandwidth (ANF/FNA request and non-PnP data), ULA RX/TX counters, UBR TX backpressure |
| QAT | 0x13693726 | 36 | Per QAT device (x2): transaction count, read/GP latency (max/accumulated), read completions, BW in/out, ATS page request and translation latency, max uTLB used |
