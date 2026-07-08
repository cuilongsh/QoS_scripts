#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re
import pandas as pd

def parse_txt(file_path):
    """Parse txt to extract COS1-4 local_memBW"""
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    pairs = re.findall(r'(COS[1-4]):local_memBW=(\d+)', content)
    if not pairs:
        raise ValueError("No COS data found!")
    df = pd.DataFrame(pairs, columns=['COS', 'local_memBW'])
    df['local_memBW'] = pd.to_numeric(df['local_memBW'])
    df['sample'] = df.index // 4
    df_pivot = df.pivot(index='sample', columns='COS', values='local_memBW')
    for c in ['COS1', 'COS2', 'COS3', 'COS4']:
        if c not in df_pivot.columns:
            df_pivot[c] = pd.NA
    df_pivot = df_pivot[['COS1', 'COS2', 'COS3', 'COS4']]
    return df_pivot.reset_index(drop=True)

def compute_single_peak(df):
    for cos in ['COS1', 'COS2', 'COS3', 'COS4']:
        peak_val = df[cos].max()
        peak_idx = df[cos].idxmax()
        df[f'{cos}_peakRegion'] = False
        df.loc[peak_idx, f'{cos}_peakRegion'] = True
        df[f'{cos}_peakAvg'] = peak_val
    return df

def compute_18s_window(df, window=18):
    best_windows = {}
    for cos in ['COS1', 'COS2', 'COS3', 'COS4']:
        best_avg = None
        best_start = None
        for i in range(len(df) - window + 1):
            avg = df.loc[i:i+window-1, cos].mean()
            if best_avg is None or avg > best_avg:
                best_avg = avg
                best_start = i
        df[f'{cos}_peakWindowRegion_18s'] = False
        df.loc[best_start:best_start+window-1, f'{cos}_peakWindowRegion_18s'] = True
        df[f'{cos}_peakWindowAvg_18s'] = best_avg
        best_windows[cos] = best_start
    return df, best_windows

def compute_10s_core(df, best_windows, window18=18, window10=10):
    for cos in ['COS1', 'COS2', 'COS3', 'COS4']:
        start = best_windows[cos]
        mid_start = start + (window18 - window10) // 2
        mid_end = mid_start + window10 - 1
        avg10 = df.loc[mid_start:mid_end, cos].mean()
        df[f'{cos}_peakWindowRegion_10s'] = False
        df.loc[mid_start:mid_end, f'{cos}_peakWindowRegion_10s'] = True
        df[f'{cos}_peakWindowAvg_10s'] = avg10
    return df

def apply_mask(df):
    for cos in ['COS1', 'COS2', 'COS3', 'COS4']:
        region18 = f'{cos}_peakWindowRegion_18s'
        avg18 = f'{cos}_peakWindowAvg_18s'
        val18 = df[avg18].iloc[0]
        df[avg18] = df[region18].apply(lambda x: val18 if x else 0)
        region10 = f'{cos}_peakWindowRegion_10s'
        avg10 = f'{cos}_peakWindowAvg_10s'
        val10 = df[avg10].iloc[0]
        df[avg10] = df[region10].apply(lambda x: val10 if x else 0)
    return df

def main():
    input_file = "mbm_import.txt"
    output_file = "cos_local_memBW_final.xlsx"
    df = parse_txt(input_file)
    df = compute_single_peak(df)
    df, best_windows = compute_18s_window(df)
    df = compute_10s_core(df, best_windows)
    df = apply_mask(df)
    df.to_excel(output_file, index=False)
    print(f"Done! Output: {output_file}")

if __name__ == "__main__":
    main()
