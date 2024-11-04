# Convert a memgraph export into a 3d-force-graph compatible export
# Memgraph: https://memgraph.com/
# 3D Force Graph: https://github.com/vasturiano/3d-force-graph
# Example usage:
# python3 bin/memgraph-to-3dfg.py --input data/memgraph-exports/panama-papers.json --output data/collection/panama-papers/blocks.json
#
import json
import argparse

def convert_memgraph_to_3dfg(input_path, output_path):
    with open(input_path, 'r') as file:
        data = [json.loads(line) for line in file]
    
    nodes = []
    links = []
    
    # Process each path in the Memgraph JSON export
    for entry in data:
        for node in entry["path"]["nodes"]:
            if not any(n["id"] == node["id"] for n in nodes):
                nodes.append({
                    "id": node["id"],
                    "label": node["labels"][0] if node["labels"] else "Unknown",
                    **node["properties"]
                })
        
        for relationship in entry["path"]["relationships"]:
            links.append({
                "source": relationship["start"],
                "target": relationship["end"],
                "label": relationship["label"]
            })
    
    # 3D-force-graph compatible format
    output_data = {
        "nodes": nodes,
        "links": links
    }
    
    with open(output_path, 'w') as outfile:
        json.dump(output_data, outfile, indent=4)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Memgraph JSON to 3D-force-graph JSON")
    parser.add_argument("--input", required=True, help="Path to the input Memgraph JSON file")
    parser.add_argument("--output", required=True, help="Path to the output JSON file in 3D-force-graph format")
    
    args = parser.parse_args()
    
    convert_memgraph_to_3dfg(args.input, args.output)
