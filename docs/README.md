# Wyvern Protocol

Wyvern 是一种数字资产交易协议，主要为了数字资产提供了一对一的交换能力。比如，我们可以用于 进行 NFT 和任何代币进行交易，或者用于代币与代币之间的兑换交易。Wyvern 有以下三点特性：

- 支持交易任何不可更改的资产，无论是 ERC20/ERC1155/ERC721；
- 支持所有的 EVM 平台部署，并为开发者提供 EVM 平台上资产交换的能力；
- 大大节省用户进行交易时产生的 Gas 费用；
- 开源；

## 协议描述

### 注册代理

Wyvern 协议中提供了 Proxy 的实现，它主要用作账户代理，比如账户 A 中需要卖出一个 NFT 资产，那么在 Wyvern 协议中，需要先注册一个代理（首次交易需要），并且为它授予转移（无论 ERC20/ERC721/ERC1155，都提供了这种授权的能力） NFT 的权利，之后的交易只需要有代理来与买方进行交易即可。这种方式可以为卖家省去每次进行交易的 Gas 费用，卖家只需要支付一次代理注册时产生的 Gas 费用。


### 

![](./images/Wyvern%20Protocol01.png)

### 注册代理合约

```javascript
const {
  tokenId,      /* NFT TokenID */
  sellAmount,   /* 售卖份数 */
  sellingPrice, /* 售卖的单份价格 */
  buyAmount,    /* 买的份数 */
  account_a,    /* 卖方账户 */
  account_b,    /* 买方账户 */
  account_c,    /* 中间商 */
  account_d,    /* 作者账户 */
  royalty,      /* 版税 */
  commission,   /* 手续费 */
} = options
// 部署合约
let { exchange, registry, statici, atomicizer } = await deploy_core_contracts()
let [erc20, erc1155] = await deploy([TestERC20, TestERC1155])
// 注册代理合约，初始化钱包时需要签约代理 (卖方第一次发布作品时需要的操作)
await registry.registerProxy({ from: account_a })
let proxy1 = await registry.proxies(account_a)
assert.equal(true, proxy1.length > 0, 'no proxy address for account a')
await registry.registerProxy({ from: account_b })
let proxy2 = await registry.proxies(account_b)
assert.equal(true, proxy2.length > 0, 'no proxy address for account b')
let totalMintAmount = buyAmount * sellingPrice
// 在账户 B 中为代理合约授予指定的转账金额权限 (买方第一次购买 NFT 时需要的操作)
await erc20.approve(proxy2, totalMintAmount, { from: account_b })
// 为账户 B 铸造一些的代币 (测试步骤)
await erc20.mint(account_b, totalMintAmount)
// 在账户 A 中为代理合约授予允许转走 NFT 的权限 (卖方第一次发布作品时需要的操作)
await erc1155.setApprovalForAll(proxy1, true, { from: account_a })
// 为账户 A 铸造指定的 NFT 数量 (测试步骤)
await erc1155.mint(account_a, tokenId, sellAmount)
```

### NFT与代币兑换交易

### NFT与代币兑换交易(含手续费)

```javascript
// 获取 Atomiczer.atomicize 函数调用地址
const abi = [{ 'constant': false, 'inputs': [{ 'name': 'addrs', 'type': 'address[]' }, { 'name': 'values', 'type': 'uint256[]' }, { 'name':'calldataLengths', 'type': 'uint256[]' }, { 'name': 'calldatas', 'type': 'bytes' }], 'name': 'atomicize', 'outputs': [], 'payable': false,'stateMutability': 'nonpayable', 'type': 'function' }]
const atomicizerc = new web3.eth.Contract(abi, atomicizer.address)
// 交易的总金额
let tradingAmount = buyAmount * sellingPrice
// 手续费
let commissionAmount = commission * tradingAmount
// 版税
let royaltyAmount = royalty * (tradingAmount - commissionAmount)
// 卖家收到的金额
let finalAmount = tradingAmount - commissionAmount - royaltyAmount

console.log("tradingAmount:     %d", tradingAmount)
console.log("commissionAmount:  %d", commissionAmount)
console.log("royaltyAmount:     %d", royaltyAmount)
console.log("finalAmount:       %d", finalAmount)

// 获取 ERC1155 实例
const erc1155c = new web3.eth.Contract(erc1155.abi, erc1155.address)
// 获取 ERC20 实例
const erc20c = new web3.eth.Contract(erc20.abi, erc20.address)

// 获取函数签名
const selectorOne = web3.eth.abi.encodeFunctionSignature('anyERC1155ForERC20(bytes,address[7],uint8[2],uint256[6],bytes,bytes)')
const selectorTwo = web3.eth.abi.encodeFunctionSignature('anyERC20ForERC1155(bytes,address[7],uint8[2],uint256[6],bytes,bytes)')
// 设置订单处理时所需的参数
const params1 = web3.eth.abi.encodeParameters(
  ['address[2]', 'uint256[3]'],
  [[erc1155.address, atomicizer.address], [tokenId, buyAmount, sellingPrice]]
)
const params2 = web3.eth.abi.encodeParameters(
  ['address[2]', 'uint256[3]'],
  [[atomicizer.address, erc1155.address], [tokenId, sellingPrice, buyAmount]]
)
const one = {
  // 注册代理合约地址
  registry: registry.address,
  // 卖家地址
  maker: account_a,
  // StaticMarket 合约部署地址
  staticTarget: statici.address,
  // 告知当前订单如何处理 Fill 值
  staticSelector: selectorOne,
  // staticSelector 部分参数值
  staticExtradata: params1,
  // 填充最大值为当前作品卖的份数
  maximumFill: sellAmount,
  // 当前作品的起售时间
  listingTime: '0',
  // 当前作品的停售时间
  expirationTime: '10000000000',
  // 自增/随机 salt
  salt: '11'
}
const two = {
  // 注册代理合约地址
  registry: registry.address,
  // 买家地址
  maker: account_b,
  // StaticMarket 合约部署地址
  staticTarget: statici.address,
  // 告知当前订单如何处理 Fill 值
  staticSelector: selectorTwo,
  // staticSelector 部分参数值
  staticExtradata: params2,
  // 填充最大值为当前交易的总金额
  maximumFill: buyAmount * sellingPrice,
  // 当前订单的开始时间
  listingTime: '0',
  // 当前订单的结束时间
  expirationTime: '10000000000',
  // 自增/随机 salt
  salt: '12'
}
// (NFT 转让) A 账户转让 1 * NFT => B 账户
const firstData = erc1155c.methods.safeTransferFrom(
  account_a,
  account_b,
  tokenId,
  buyAmount,
  "0x"
).encodeABI()
// (交易金额转账) B 账户转让 1 * 10000 * 0.75 代币 => A 账户
const data2 = erc20c.methods.transferFrom(
  account_b,
  account_a,
  finalAmount
).encodeABI()
// (手续费转帐) B 账户转让 1 * 10000 代币 => C 账户
const data3 = erc20c.methods.transferFrom(
  account_b,
  account_c,
  commissionAmount
).encodeABI()
// (版税转账) B 账户转让 1 * 10000 代币 => D 账户
const data4 = erc20c.methods.transferFrom(
  account_b,
  account_d,
  royaltyAmount
).encodeABI()
// 将转账逻辑作为一个批量执行
// bytes 转为 16 hex string 为 0x，所以需要 -2，并且 / 2（因为每个字节显示为两位字符)
const secondData = atomicizerc.methods.atomicize(
  [erc20.address, erc20.address, erc20.address],
  [0, 0, 0],
  [(data2.length - 2) / 2, (data3.length - 2) / 2, (data4.length - 2) / 2],
  data2 + data3.slice(2) + data4.slice(2)
).encodeABI()
const firstCall = { target: erc1155.address, howToCall: 0, data: firstData }
const secondCall = { target: atomicizer.address, howToCall: 1, data: secondData }
// 签名确认
let sigOne = await exchange.sign(one, account_a)
let sigTwo = await exchange.sign(two, account_b)

// 最终交易
await exchange.atomicMatchWith(
  one,
  sigOne,
  firstCall,
  two,
  sigTwo,
  secondCall,
  ZERO_BYTES32,
  // 默认为卖方地址
  { from: account_a }
)

// 查账确认
let [account_a_erc20_balance,
  account_b_erc20_balance,
  account_c_erc20_balance,
  account_d_erc20_balance,
  account_b_erc1155_balance
] = await Promise.all([
  erc20.balanceOf(account_a),
  erc20.balanceOf(account_b),
  erc20.balanceOf(account_c),
  erc20.balanceOf(account_d),
  erc1155.balanceOf(account_b, tokenId)
])
console.log("account_a balance: %d", account_a_erc20_balance.toNumber())
console.log("account_b balance: %d, erc1155: %s", account_b_erc20_balance.toNumber(), account_b_erc1155_balance.toNumber())
console.log("account_c balance: %d", account_c_erc20_balance.toNumber())
console.log("account_d balance: %d", account_d_erc20_balance.toNumber())
assert.equal(account_a_erc20_balance.toNumber(), finalAmount, 'Incorrect ERC20 balance')
assert.equal(account_b_erc1155_balance.toNumber(), buyAmount, 'Incorrect ERC1155 balance')
```

## Development

Wyvern 采用 truffle 工具来，并提供相关的自动化脚本对合约进行构建部署测试。

### Test

```bash
yarn testrpc
```

启动 ganache 测试链：

- networkId：50
- port：8545

```bash
yarn test
```

运行单元测试，单元测试文件在 [test](../test/) 文件夹中。

### Linting

```bash
yarn lint
```

运行代码规范检查，可自动识别代码对齐、代码命名等规则，其规则配置文件为 [.soliumrc.json](../.soliumrc.json)，如果有不需要检查的文件则可以在 [.soliumignore](../.soliumignore) 文件中添加即可。

### Static analyze

```bash
yarn analyze
```

运行静态分析，Wyvern 使用 [Slither](https://github.com/crytic/slither) 作为静态分析工具，可以分析出大部分 Solidity 代码的[安全问题](https://github.com/crytic/slither#detectors)。

### Deploy

```
yarn run truffle deploy --network [network]
```

执行 [编译部署](https://learnblockchain.cn/docs/truffle/getting-started/running-migrations.html)，对应的部署网络可在 [truffle.js] 中配置，如果要发布在公链上，需要在 [sample.env](../sample.env) 文件中进行私钥的配置。