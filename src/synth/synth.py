import os
import shutil
import subprocess
import re

def check_and_append_report_status(report_path):
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[0;33m"
    RESET = "\033[0m"

    summary = []

    # Check if synthesis failed
    synth_error_codes = []
    if os.path.exists('synth-error-codes'):
        with open('synth-error-codes', 'r') as f:
            synth_error_codes = [line.strip() for line in f if line.strip()]

    synth_log_path = report_path
    if not os.path.isfile(synth_log_path):
        summary.append(f"{RED}Synthesis failed{RESET}")
        return summary

    with open(synth_log_path, 'r') as f:
        synth_log = f.read()

    synth_failed = any(re.search(rf'\b{re.escape(code)}\b', synth_log, re.IGNORECASE) for code in synth_error_codes)
    if synth_failed:
        summary.append(f"{RED}Synthesis failed{RESET}")
        return summary

    # Check for timing
    timing_met = False
    if os.path.exists("reports/timing.rpt"):
        with open("reports/timing.rpt", 'r') as f:
            timing_content = f.read()
            timing_met = bool(re.search(r'slack \(MET\)', timing_content, re.IGNORECASE))

    if timing_met:
        summary.append(f"{GREEN}Timing Met{RESET}")
    else:
        summary.append(f"{RED}Timing Not Met{RESET}")
        return summary

    # Check for warnings
    if re.search(r'warning', synth_log, re.IGNORECASE):
        summary.append(f"{YELLOW}Synthesis finished with warnings{RESET}")
    else:
        summary.append(f"{GREEN}Synthesis Successful{RESET}")

    return summary

def run_synth_on_files(folder_path):
    for root, dirs, files in os.walk(folder_path):
        for file_name in files:
            if file_name.endswith('.sv'):
                module_name = file_name.split('_code')[0]
                synth_command = f"make synth HDL_SRCS={os.path.join(root, file_name)} DESIGN_TOP={module_name}"
                file_path = os.path.join(root, file_name)

                try:
                    print(f"Running synth on: {file_name}")
                    subprocess.run(synth_command, shell=True, check=True)
                except subprocess.CalledProcessError as e:
                    print(f"synth failed for {file_name}: {e}")

                reports_folder = os.path.join('reports')
                relative_path = os.path.relpath(root, folder_path)
                report_subfolder = os.path.join('../reports', relative_path)
                try:
                    subprocess.run(f"./run.sh", shell=True, check=True)
                except subprocess.CalledProcessError as e:
                    print(f"Failed to run report script for {file_name}: {e}")
                metric_file = os.path.join(reports_folder, 'metrics.txt')
                synth_report = os.path.join(reports_folder, 'synthesis.log')
                sta_report = os.path.join(reports_folder, 'sta.log')
                timing_report = os.path.join(reports_folder, 'timing.rpt')
                # lint_report = os.path.join(reports_folder, 'lint.log')
                


                if not os.path.exists(report_subfolder):
                    os.makedirs(report_subfolder)

                if os.path.exists(metric_file):
                    new_metric_name = f"{file_name.split('.')[0]}_metrics.txt"
                    new_metric_path = os.path.join(report_subfolder, new_metric_name)
                    shutil.copy(metric_file, new_metric_path)
                    print(f"metrics saved as: {new_metric_path}")

                # if os.path.exists(synth_report):
                #     new_report_name = f"{file_name.split('.')[0]}_synth.log"
                #     new_report_path = os.path.join(report_subfolder, new_report_name)
                #     shutil.copy(synth_report, new_report_path)
                #     print(f"synth report saved as: {new_report_path}")

                    # Append summary to the copied log
                    # summary_lines = check_and_append_report_status(new_report_path)
                    # with open(new_report_path, 'a') as log_file:
                    #     log_file.write("\n\n===== SYNTHESIS SUMMARY =====\n")
                    #     for line in summary_lines:
                    #         log_file.write(line + '\n')
                # else:
                #     print(f"No synth report found for {file_name}")
                # if os.path.exists(sta_report):
                #     new_sta_report_name = f"{file_name.split('.')[0]}_sta.log"
                #     new_sta_report_path = os.path.join(report_subfolder, new_sta_report_name)
                #     shutil.copy(sta_report, new_sta_report_path)
                #     print(f"sta report saved as: {new_sta_report_path}")
                # else:
                #     print(f"No sta report found for {file_name}")
                # if os.path.exists(timing_report):
                #     new_timing_report_name = f"{file_name.split('.')[0]}_timing.rpt"
                #     new_timing_report_path = os.path.join(report_subfolder, new_timing_report_name)
                #     shutil.copy(timing_report, new_timing_report_path)
                #     print(f"timing report saved as: {new_timing_report_path}")
                # else:
                #     print(f"No timing report found for {file_name}")
                # if os.path.exists(lint_report):
                #     new_lint_report_name = f"{file_name.split('.')[0]}_lint.log"
                #     new_lint_report_path = os.path.join(report_subfolder, new_lint_report_name)
                #     shutil.copy(lint_report, new_lint_report_path)
                #     print(f"lint report saved as: {new_lint_report_path}")
                # else:
                #     print(f"No lint report found for {file_name}")
# Path to .sv files
folder_path = '../../code'

# Execute
run_synth_on_files(folder_path)
