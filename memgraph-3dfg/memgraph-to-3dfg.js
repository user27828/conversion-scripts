/**
 * Convert a memgraph export into a 3d-force-graph compatible blocks.json export
 * Example Usage:
 * node memgraph-to-3dfg.js --input memgraph-file.json --output blocks.json
 */
import fs from "fs";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

function convertMemgraphTo3DFG(inputPath, outputPath) {
  const data = fs
    .readFileSync(inputPath, "utf8")
    .split("\n")
    .filter((line) => line)
    .map((line) => JSON.parse(line));

  const nodesMap = new Map();
  const links = [];

  data.forEach((entry) => {
    entry.path.nodes.forEach((node) => {
      if (!nodesMap.has(node.id)) {
        nodesMap.set(node.id, {
          id: node.id,
          label: node.labels[0] || "Unknown",
          ...node.properties,
        });
      }
    });

    entry.path.relationships.forEach((relationship) => {
      links.push({
        source: relationship.start,
        target: relationship.end,
        label: relationship.label,
      });
    });
  });

  const outputData = {
    nodes: Array.from(nodesMap.values()),
    links: links,
  };

  fs.writeFileSync(outputPath, JSON.stringify(outputData, null, 4));
}

const argv = yargs(hideBin(process.argv))
  .option("input", {
    alias: "i",
    description: "Path to the input Memgraph JSON file",
    type: "string",
    demandOption: true,
  })
  .option("output", {
    alias: "o",
    description: "Path to the output JSON file in 3D-force-graph format",
    type: "string",
    demandOption: true,
  })
  .help()
  .alias("help", "h").argv;

convertMemgraphTo3DFG(argv.input, argv.output);
