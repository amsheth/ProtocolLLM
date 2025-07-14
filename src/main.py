import openai
import os
import yaml
import pandas as pd
import sys
import json

from prompt import prompt_gpt, prompt_gpt_iter
from prompt import get_rag
import argparse
import datetime
openai_api_key = os.environ.get("OPENAI_API_KEY")

openai.api_key = ""

timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Process FPGA protocol configurations.")
    parser.add_argument("--config", type=str, default="configs/base.yaml", help="Path to the configuration YAML file.")
    parser.add_argument("--dataset", type=str, default="easy", help="Dataset name to process.")
    parser.add_argument("--output", type=str, default="outputs", help="Path to save the output JSON file.")
    parser.add_argument("--model", type=str, default="alias-code", help="Model name to use for processing.")
    parser.add_argument("--protocol", type=str, default="i2c", help="Protocol type to process.")
    parser.add_argument("--use_rag", action="store_true", help="Enable Retrieval-Augmented Generation (RAG).")
    parser.add_argument("--iter", action="store_true", help="Enable iteration")

    args = parser.parse_args()

    # Ensure the 'CMDs' directory exists
    os.makedirs('CMDs', exist_ok=True)
    with open('CMDs/commands.cmd', 'a') as f:
        f.write(' '.join(sys.argv) + '\n')

    config_path = args.config
    with open(config_path, "r") as file:
        config = yaml.safe_load(file)
    protocol = args.protocol
    try:
        prompts = [v for v in config.get(protocol, {}).values()]
        # print(prompts)
        


    except AttributeError:
        sys.exit(f"Error: Invalid configuration format. '{protocol}' section is missing or malformed.")        

    output_dir = os.path.join("outputs", args.protocol, args.model)
    output_filename = os.path.join(output_dir, f"{args.protocol}_{args.dataset}_{args.model}_RAG{args.use_rag}.json")
    model_name = args.model

    if args.iter:
        if not os.path.exists(output_filename):
            print("Output file not found. Generating initial output.")
            output = prompt_gpt(prompts, use_rag=args.use_rag, model_name=model_name)
            with open(output_filename, "w") as file:
                json.dump(output, file, indent=4)
                file.write('\n')

        # Load the corresponding lint file
        protocol_files = {
            "i2c": f"I2C_driver_code_0_RAG{args.use_rag}_lint.rpt",
            "spi": f"SPI_driver_code_0_RAG{args.use_rag}_lint.rpt",
            "axi": f"AXI4_Lite_Master_code_0_RAG{args.use_rag}_lint.rpt",
            "uart": f"UART_driver_code_0_RAG{args.use_rag}_lint.rpt",
            }
        doc_path = protocol_files.get(args.protocol)

        lint_filename = os.path.join("reports", args.protocol, args.model, doc_path)

        if not os.path.exists(lint_filename):
            print(f"Lint file not found: {lint_filename}. Skipping refinement.")
        else:
            # Parse the lint file for errors
            def parse_lint_report(report_path):
                errors = []
                warnings = []
                syntax_issues = []

                try:
                    with open(report_path, "r") as file:
                        for line in file:
                            if "Error" in line:  # Adjust based on the lint report format
                                errors.append(line.strip())
                            elif "Warning" in line:  # Adjust based on the lint report format
                                warnings.append(line.strip())
                            elif "Syntax" in line:  # Adjust based on the lint report format
                                syntax_issues.append(line.strip())
                except FileNotFoundError:
                    print(f"Error: Lint report file not found: {report_path}")
                except Exception as e:
                    print(f"Error: Failed to parse lint report: {e}")

                return {
                    "errors": errors,
                    "warnings": warnings,
                    "syntax_issues": syntax_issues,
                }

            errors = parse_lint_report(lint_filename)
            if not errors:
                print("No errors found in the lint report. No refinement needed.")
            else:
                # Combine all errors into a single prompt
                combined_errors = "\n".join(msg for msgs in errors.values() for msg in msgs)
                refined_prompt = [
                    {
                        "role": "user",
                        "content": f"Refine the following code to fix these errors:\n\n{combined_errors}. Correct the entire code. Give full code as the output."
                    }
                ]

                # Add the previous conversation context
                with open(output_filename, "r") as file:
                    previous_output = json.load(file)
                    refined_prompt.insert(0, {"role": "user", "content": previous_output["prompt_0"]})
                    refined_prompt.insert(1, {"role": "assistant", "content": previous_output["answer_0"]})
                refined_dir = os.path.join("refined", args.protocol, args.model)
                refined_output_filename = os.path.join(refined_dir, f"{args.protocol}_{args.dataset}_{args.model}_RAG{args.use_rag}.json")

                refined_output = prompt_gpt_iter([refined_prompt], use_rag=False, model_name=model_name)

                # Save the refined output
                with open(refined_output_filename, "w") as file:
                    json.dump(refined_output, file, indent=4)
                    file.write('\n')
                print(f"Refined output saved to {refined_output_filename}")

    else:
        if args.use_rag:
            protocol_docs = {
            "i2c": "docs/I2C/i2c.pdf",
            "spi": "docs/SPI/spi.pdf",
            "axi": "docs/AXI/AXI_Spec.pdf",
            "uart": "docs/UART/uart.pdf",
            }
            doc_path = protocol_docs.get(args.protocol)
            prompts = get_rag(doc_path, prompts)

        output = prompt_gpt(prompts, use_rag=args.use_rag, model_name=model_name)
        os.makedirs(output_dir, exist_ok=True)

        with open(output_filename, "w") as file:
            json.dump(output, file, indent=4)
            file.write('\n')
