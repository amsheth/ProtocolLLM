import os
import json
import re

def extract_module_name(code):
    # Regular expression to match the module declaration
    match = re.search(r"module\s+(\w+)", code)
    if match:
        return match.group(1)
    return "unknown_module"  # Default if no module name is found


def extract_code_until_endmodule(code):
    # Cut the code to everything until 'endmodule', removing any part after it
    endmodule_pos = code.lower().find('\n```')
    if endmodule_pos != -1:
        return code[:endmodule_pos].strip()  # Return the code before 'endmodule'
    return code.strip()  # Return the original code if 'endmodule' is not found


# Function to recursively search for .json files in a folder and its subfolders
def process_json_files(folder_path, output_folder):
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            if file.endswith('.json'):
                file_path = os.path.join(root, file)
                with open(file_path, 'r') as f:
                    try:
                        data = json.load(f)
                        
                        # Loop through each prompt-answer pair in the JSON data
                        for key, value in data.items():
                            print(f"Processing {key}")
                            if key.startswith('answer_'):
                                # Extract the answer code (remove the triple backticks for formatting)
                                # Check if the code block starts with systemverilog

                                code=''
                                # match = re.search(r"```systemverilog\s+(.*?)```", value, re.DOTALL)
                                match = re.search(r"```systemverilog\s*(.*?)```", value, re.DOTALL)
                                if match:
                                    code=match.group(1).strip()

                                # Fallback: look for generic triple-backtick code blocks
                                match = re.search(r"```(?:\w*\n)?(.*?)```", value, re.DOTALL)
                                if match:
                                    code= match.group(1).strip()
                                match = re.search(r"module\s+\w+\s*\(.*?endmodule", value, re.DOTALL)
                                if match:
                                    code = match.group(0).strip()
                                # print(a)
                                # print('------------------------------------------------------')

                                # If no code block is found, just return the whole value
                                # return value.strip()


                                # if value.startswith("```systemverilog\n"):
                                #     code = value[16:].strip("```")  # Strip the first 16 characters (```systemverilog\n)
                                #     print("systemverilog")
                                # elif value.startswith("```systemverilog"):
                                #     return value[len("```systemverilog"):].strip("` \n")
                                # elif value.startswith("module"):
                                #     code = value.strip("```")
                                #     print("module")
                                # else:
                                #     code = value.strip("```").strip("systemverilog\n")
                                #     a=value.strip("module")
                                    # print(a)
                                    
                                code = extract_code_until_endmodule(code)
                                                            
                                module_name = extract_module_name(code)
                                
                                # Generate a filename based on the module name, e.g., I2C_driver.sv
                                # filename = f"{module_name}.sv"

                                # Generate a filename based on the key, e.g., answer_0 -> code_0.sv
                                filename = f"{module_name}_code_{key.split('_')[1]}_{file.split('_')[-1][:-5]}.sv"
                                
                                # Create the full path for the output file, preserving the folder structure
                                output_path = os.path.join(output_folder, root.replace(folder_path, '').lstrip(os.sep), filename)
                                
                                # Ensure the directory exists
                                os.makedirs(os.path.dirname(output_path), exist_ok=True)

                                # Save the code to the output file
                                with open(output_path, 'w') as output_file:
                                    output_file.write(code)

                                print(f"Saved {output_path}")
                    except json.JSONDecodeError:
                        print(f"Error decoding JSON in file: {file_path}")
                    except Exception as e:
                        print(f"Error processing file {file_path}: {e}")

# Input and output folder paths
# input_folder = 'refined'
# output_folder = '../refined_code'

input_folder = 'outputs'
output_folder = '../code'

# Process all JSON files in the folder and subfolders
process_json_files(input_folder, output_folder)





















