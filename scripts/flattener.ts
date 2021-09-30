const fs = require("fs")
const path = require("path")

interface AstNode {
  id: number;
  literals?: string[];
  nodeType: string;
  file?: string;
  absolutePath?: string;
  name: string;
}

interface Ast {
  absolutePath: string;
  exportedSymbols: {
    [a: string]: number[]
  }[];
  id: number;
  nodeType: string;
  nodes?: AstNode[]
}

interface CompiledContract {
  contractName: string;
  abi: string;
  metadata: string;
  bytecode: string;
  deployedBytecode: string;
  immutableReferences: unknown;
  generatedSources: any[];
  deployedGeneratedSources: any[];
  source: string;
  ast: Ast
}

interface FlattenedSource {
  source: string;
  raw: string;
  sourceFiltered: string;
  imports: Set<string>;
  contractName: string;
  flattened: string;
}

class RecursiveFlattener {
  rawContracts: Map<string, CompiledContract> = new Map<string, CompiledContract>();
  flattenedContracts: Map<string, FlattenedSource> = new Map<string, FlattenedSource>();

  sourceDir: string = ''
  outDir: string = ''

  static pathToFileName(p: string) {
    return p.split('/').pop().replace('.sol', '')
  }

  static getSpdxFromSource(source: string) {
    const index = source.indexOf('SPDX-License-Identifier:')
    const newLine = source.indexOf('\n', index)
    return source
      .substring(index, newLine)
      .split(':')
      .pop()
      .replace(' ', '');
  }

  async init(sourceDir, outDir) {
    if (!fs.existsSync(outDir)) {
      await fs.mkdir(outDir, () => {
      })
    }
    const names = (await fs.readdirSync(sourceDir))
    names.forEach(name => {
      const f = JSON.parse(fs.readFileSync(path.join(sourceDir, name)).toString())
      this.rawContracts.set(f.contractName, f)
    })
    this.sourceDir = sourceDir;
    this.outDir = outDir;
    await this.run()
  }

  async run() {
    for (const contractName of Array.from(this.rawContracts.keys())) {
      await this.flattenSingle(contractName)
    }
  }

  async flattenSingle(contractName: string) {
    if (this.flattenedContracts.has(contractName)) return;

    const contract = this.rawContracts.get(contractName);

    const flattened = {
      contractName,
      source: '',
      sourceFiltered: '',
      raw: contract.source,
      imports: new Set<string>(),
      flattened: ''
    }

    for (const node of contract.ast.nodes) {
      let nodeContract;
      if (node.nodeType === 'ContractDefinition' || contract.abi.length == 0) {
        flattened.source += contract.source;
        break;
      }
      if (node.nodeType !== 'ImportDirective') continue;
      const fileName = node.absolutePath ? RecursiveFlattener.pathToFileName(node.absolutePath) : node.name;


      if (fileName === contractName) continue;
      flattened.imports.add(fileName)

      nodeContract = this.flattenedContracts.get(fileName)
      if (!nodeContract) {
        await this.flattenSingle(fileName)
        nodeContract = this.flattenedContracts.get(fileName)
      }

      flattened.source += nodeContract.source;
    }
    flattened.sourceFiltered = contract.source.replace(/import ["|'].*["|'];/g, '')
    flattened.sourceFiltered = flattened.sourceFiltered.replace(/\/\/ SPDX-License-Identifier:.*\n/g, '')
    // flattened.sourceFiltered = '// SPDX-License-Identifier: MIT\n' + flattened.sourceFiltered;
    flattened.source = flattened.source.replace(/import ["|'].*["|'];/g, '')
    flattened.source = flattened.source.replace(/\/\/ SPDX-License-Identifier:.*\n/g, '')
    // flattened.source = '// SPDX-License-Identifier: MIT\n' + flattened.source;

    const filtered = new Set<string>();
    flattened.imports.forEach(i => {
      const con = this.flattenedContracts.get(i)
      con.imports.forEach(j => {
        const cox = this.flattenedContracts.get(j)
        if (cox) {
          con.imports.forEach(k => {
            filtered.add(k)
          })
        }
        filtered.add(j)
      })
      filtered.add(i)
    })

    flattened.flattened = '// SPDX-License-Identifier: MIT\n';
    flattened.imports.forEach(i => {
      flattened.flattened += this.flattenedContracts.get(i).sourceFiltered
    })

    fs.writeFileSync(path.join(this.outDir, flattened.contractName + ".sol"), flattened.flattened)

    this.flattenedContracts.set(contractName, flattened);
  }
}

const flattener = new RecursiveFlattener();
flattener.init(path.join(__dirname, "../build/contracts"), path.join(__dirname, "flattener-out"))
//
// async function flattener() {
//   const sourceDir = path.join(__dirname, "../build/contracts");
//   const names = (await fs.readdirSync(sourceDir))
//   const files = {}
//   names.forEach(name => {
//     const f = JSON.parse(fs.readFileSync(path.join(sourceDir, name)).toString())
//     files[f.contractName] = f
//   })
//
//   Object.values(files).forEach((contract: CompiledContract) => {
//     let fileSource = contract.source;
//     let flattened = ''
//     const nodes = contract.ast.nodes;
//     nodes.forEach(node => {
//       if (!node.absolutePath) return;
//
//       const arr = node.absolutePath.split('/')
//       const contractName = arr[arr.length - 1].replace('.sol', '')
//
//       if (!files[contractName]) return;
//
//       const nodeContract = files[contractName]
//       fileSource = fileSource.replace("import " + node.absolutePath + ";", "");
//       flattened += nodeContract.source;
//     })
//     flattened += fileSource;
//   })
//
// }
//
// flattener()
