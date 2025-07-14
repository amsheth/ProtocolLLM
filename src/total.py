import pandas as pd
import os
import re

def parse_metrics(metrics_path, protocol, llm):
    metrics = {
        "File": os.path.basename(metrics_path).replace("_metrics.txt", ""),
        "Protocol": protocol,
        "LLM": llm,
        "Lint": "N/A",
        "Synthesis": "N/A",
        "Timing": "N/A",
        "Power (W)": "N/A",
        "Area (µm²)": "N/A"
    }

    if not os.path.exists(metrics_path):
        return metrics

    with open(metrics_path, 'r') as f:
        lines = f.readlines()
        for line in lines:
            line = line.strip()

            if "No lint errors" in line:
                metrics["Lint"] = "✓"
            if "Lint warnings found" in line:
                metrics["Lint"] = "⚠"
            if "Verilator" in line and "ERROR" in line:
                metrics["Lint"] = "✗"

            if "No synthesis errors" in line:
                metrics["Synthesis"] = "✓"
            if "Synthesis errors found" in line:
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

def compute_score(row):
    score = 0
    if row["Lint"] == "✓":
        score += 1
    if row["Synthesis"] == "✓":
        score += 1
    return score

def safe_float(x):
    try:
        return float(x)
    except:
        return None

def generate_final_table(report_root):
    all_metrics = []
    for subdir, _, files in os.walk(report_root):
        for file in files:
            if file.endswith("_metrics.txt"):
                metrics_path = os.path.join(subdir, file)

                parts = os.path.normpath(subdir).split(os.sep)
                if len(parts) >= 3:
                    protocol = parts[-2]     # e.g., spi
                    llm = parts[-1]          # e.g., gpt-4.1
                else:
                    protocol = "unknown"
                    llm = "unknown"

                metrics = parse_metrics(metrics_path, protocol, llm)
                all_metrics.append(metrics)

    if not all_metrics:
        print("No metric files found.")
        return

    df = pd.DataFrame(all_metrics)
    df = df.sort_values(["Protocol", "LLM", "File"])
    output_path = os.path.join(report_root, "final_metrics_table.txt")
    df.to_string(buf=open(output_path, "w"), index=False)

    # Score + Normalize numeric fields
    df["Score"] = df.apply(compute_score, axis=1)
    df["Power (W)"] = df["Power (W)"].apply(safe_float)
    df["Area (µm²)"] = df["Area (µm²)"].apply(safe_float)

    # Group by LLM and Protocol
    score_summary = df.groupby(["LLM", "Protocol"]).agg(
        Total_Designs=("Score", "count"),
        Designs_with_Metrics=("Power (W)", "count"),
        Total_Score=("Score", "sum"),
        Avg_Power=("Power (W)", "mean"),
        Avg_Area=("Area (µm²)", "mean")
    )

    score_summary["Max_Score"] = score_summary["Total_Designs"] * 2
    score_summary["Score_%"] = (score_summary["Total_Score"] / score_summary["Max_Score"]) * 100
    score_summary = score_summary.sort_values(["Score_%", "LLM", "Protocol"], ascending=[False, True, True])

    print("\nLLM × Protocol Quality Summary:")
    print(score_summary.to_string(float_format="%.4f"))
    score_summary.to_csv("llm_protocol_score_summary.csv")

    # Save as GitHub Markdown
    with open("llm_protocol_score_summary.md", "w") as f:
        f.write("## 📊 LLM × Protocol Quality Summary\n\n")
        f.write("| LLM | Protocol | Total Designs | Score | Score % | Avg Power (W) | Avg Area (µm²) |\n")
        f.write("|-----|----------|----------------|--------|----------|----------------|-----------------|\n")
        for (llm, proto), row in score_summary.iterrows():
            avg_power = f"{row['Avg_Power']:.2e}" if not pd.isna(row['Avg_Power']) else "N/A"
            avg_area = f"{int(row['Avg_Area'])}" if not pd.isna(row['Avg_Area']) else "N/A"
            f.write(f"| {llm} | {proto} | {row['Total_Designs']} | {row['Total_Score']} | {row['Score_%']:.1f}% | {avg_power} | {avg_area} |\n")

    print("\n✅ Markdown table saved to: llm_protocol_score_summary.md")


# import pandas as pd

# Final step
generate_final_table("reports")

# Load the fixed-width table
df = pd.read_fwf("reports/final_metrics_table.txt")

# Save as GitHub-flavored Markdown
with open("final_metrics_table.md", "w") as f:
    f.write("| " + " | ".join(df.columns) + " |\n")
    f.write("|" + "|".join(["---"] * len(df.columns)) + "|\n")
    for _, row in df.iterrows():
        f.write("| " + " | ".join(str(x) if pd.notna(x) else "" for x in row) + " |\n")

