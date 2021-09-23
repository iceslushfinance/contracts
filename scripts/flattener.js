const fs = require("fs")
const path = require("path")

class FlattenedContract {
  rawContract = '';
  dependencies = [];
  selfSource = '';
  contractName = '';
}

class RecursiveFlattener {
  contractNames = [];
  rawContracts = [];

  async init(sourceDir, outDir) {
    const names = (await fs.readdirSync(sourceDir))
    this.contractNames = names;
    const files = {}
    names.forEach(name => {
      const f = JSON.parse(fs.readFileSync(path.join(sourceDir, name)).toString())
      files[f.contractName] = f
    })
  }
}

async function flattener() {
  const sourceDir = path.join(__dirname, "../build/contracts");
  const names = (await fs.readdirSync(sourceDir))
  const files = {}
  names.forEach(name => {
    const f = JSON.parse(fs.readFileSync(path.join(sourceDir, name)).toString())
    files[f.contractName] = f
  })

  Object.values(files).forEach(contract => {
    let fileSource = contract.source;
    let flattened = ''
    const nodes = contract.ast.nodes;
    nodes.forEach(node => {
      if (!node.file) return;

      const arr = node.file.split('/')
      const contractName = arr[arr.length - 1].replace('.sol', '')

      if (!files[contractName]) return;

      const nodeContract = files[contractName]
      fileSource = fileSource.replace("import " + node.file + ";", "");
      flattened += nodeContract.source;
    })
    flattened += fileSource;
  })

}

flattener()
