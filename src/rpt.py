import pandas as pd
import os
import re

def parse_metrics(metrics_path, protocol, llm):
    metrics = {
        "File": os.path.basename(metrics_path).replace("_metrics.txt", ""),
        "Protocol": protocol,
        "LLM": llm,
        "RAG": "Unknown",
        "Lint": "N/A",
        "Synthesis": "N/A",
        "Timing": "N/A",
        "Power (W)": "N/A",
        "Area (µm²)": "N/A"
    }

    if "RAGTrue" in metrics["File"]:
        metrics["RAG"] = "True"
    elif "RAGFalse" in metrics["File"]:
        metrics["RAG"] = "False"

    if not os.path.exists(metrics_path):
        return metrics

    with open(metrics_path, 'r') as f:
        for line in f:
            line = line.strip()
            if "No lint errors" in line:
                metrics["Lint"] = "✓"
            elif "Lint warnings found" in line:
                metrics["Lint"] = "⚠"
            elif "Verilator" in line and "ERROR" in line:
                metrics["Lint"] = "✗"

            if "No synthesis errors" in line:
                metrics["Synthesis"] = "✓"
            elif "Synthesis errors found" in line:
                metrics["Synthesis"] = "✗"

            if "Timing Met: YES" in line:
                metrics["Timing"] = "✓"
            elif "Timing Met: NO" in line or "Timing Not Met" in line:
                metrics["Timing"] = "✗"

            if "Total Power" in line:
                match = re.search(r'([0-9]+\.[0-9]+e[-+][0-9]+)', line)
                if match:
                    metrics["Power (W)"] = match.group(1)

            if "Chip Area" in line:
                match = re.search(r'([0-9]+)\s*µm²', line)
                if match:
                    metrics["Area (µm²)"] = match.group(1)

    return metrics

def safe_float(x):
    try:
        return float(x)
    except:
        return None

def generate_grouped_summary(report_root):
    all_metrics = []
    for subdir, _, files in os.walk(report_root):
        for file in files:
            if file.endswith("_metrics.txt"):
                metrics_path = os.path.join(subdir, file)
                parts = os.path.normpath(subdir).split(os.sep)
                protocol = parts[-2] if len(parts) >= 2 else "unknown"
                llm = parts[-1] if len(parts) >= 1 else "unknown"
                metrics = parse_metrics(metrics_path, protocol, llm)
                all_metrics.append(metrics)

    df = pd.DataFrame(all_metrics)

    df["Lint Pass"] = (df["Lint"] == "✓") | (df["Lint"] == "⚠")
    df["Synth Pass"] = df["Synthesis"] == "✓"
    df["Timing Pass"] = df["Timing"] == "✓"
    df["Power (W)"] = df["Power (W)"].apply(safe_float)
    df["Area (µm²)"] = df["Area (µm²)"].apply(safe_float)

    grouped = df.groupby(["LLM", "RAG", "Protocol"]).agg(
        Total_Designs=("File", "count"),
        Lint_Pass_Rate=("Lint Pass", "mean"),
        Synth_Pass_Rate=("Synth Pass", "mean"),
        Timing_Pass_Rate=("Timing Pass", "mean"),
        Avg_Power=("Power (W)", "mean"),
        Avg_Area=("Area (µm²)", "mean")
    ).reset_index()

    grouped["Lint_Pass_Rate"] = (grouped["Lint_Pass_Rate"] * 100).round(1)
    grouped["Synth_Pass_Rate"] = (grouped["Synth_Pass_Rate"] * 100).round(1)
    grouped["Timing_Pass_Rate"] = (grouped["Timing_Pass_Rate"] * 100).round(1)

    grouped = grouped.sort_values(by=["LLM", "RAG", "Protocol"])

    # Save CSV
    grouped.to_csv("final_metric_table.txt", index=False)

    # Save Markdown
    with open("final_metric_table.md", "w") as f:
        f.write("## 📊 Final Metric Table by LLM × RAG × Protocol\n\n")
        f.write("| LLM | RAG | Protocol | Total | Lint Pass (%) | Synth Pass (%) | Timing Pass (%) | Avg Power (W) | Avg Area (µm²) |\n")
        f.write("|-----|-----|----------|--------|----------------|------------------|-------------------|----------------|-----------------|\n")
        for _, row in grouped.iterrows():
            avg_power = f"{row['Avg_Power']:.2e}" if not pd.isna(row['Avg_Power']) else "N/A"
            avg_area = f"{int(row['Avg_Area'])}" if not pd.isna(row['Avg_Area']) else "N/A"
            f.write(f"| {row['LLM']} | {row['RAG']} | {row['Protocol']} | {row['Total_Designs']} | {row['Lint_Pass_Rate']}% | {row['Synth_Pass_Rate']}% | {row['Timing_Pass_Rate']}% | {avg_power} | {avg_area} |\n")

    print("✅ Saved summary as: final_metric_table.txt and final_metric_table.md")

generate_grouped_summary("reports")
