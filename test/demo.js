const WyvernAtomicizer = artifacts.require('WyvernAtomicizer')
const WyvernExchange = artifacts.require('WyvernExchange')
const WyvernStatic = artifacts.require('WyvernStatic')
const WyvernRegistry = artifacts.require('WyvernRegistry')
const TestERC20 = artifacts.require('TestERC20')
const TestERC721 = artifacts.require('TestERC721')
const TestERC1271 = artifacts.require('TestERC1271')
const TestERC1155 = artifacts.require('TestERC1155')
const StaticMarket = artifacts.require('./StaticMarket.sol')
const Utils = require('./util')

const { debug } = require('console')
const { iteratee } = require('lodash')
const Web3 = require('web3')
const provider = new Web3.providers.HttpProvider('http://localhost:8545')
const web3 = new Web3(provider)

const { wrap, ZERO_BYTES32, CHAIN_ID, NULL_SIG, assertIsRejected } = require('./util')

contract('WyvernExchange', (accounts) => {
  // Init
  let deploy_core_contracts = async () => {
    let [registry, atomicizer] = await Promise.all([WyvernRegistry.new(), WyvernAtomicizer.new()])
    let [exchange, statici] = await Promise.all([WyvernExchange.new(CHAIN_ID, [registry.address], '0x'), WyvernStatic.new(atomicizer.address)])
    await registry.grantInitialAuthentication(exchange.address)
    return { registry, exchange: wrap(exchange), atomicizer, statici }
  }

  let deploy = async contracts => Promise.all(contracts.map(contract => contract.new()))

  const any_erc1155_for_erc20_test = async (options) => {
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

    let totalMintAmount = buyAmount * sellingPrice
    // 为账户 B 铸造一些的代币 (测试步骤)
    await erc20.mint(account_b, totalMintAmount)
    // 为账户 A 铸造指定的 NFT 数量 (测试步骤)
    await erc1155.mint(account_a, tokenId, sellAmount)

    // 注册代理合约，初始化钱包时需要签约代理 (卖方第一次发布作品时需要的操作)
    await registry.registerProxy({ from: account_a })
    let proxy1 = await registry.proxies(account_a)
    assert.equal(true, proxy1.length > 0, 'no proxy address for account a')

    await registry.registerProxy({ from: account_b })
    let proxy2 = await registry.proxies(account_b)
    assert.equal(true, proxy2.length > 0, 'no proxy address for account b')

    // 在账户 A 中为代理合约授予允许转走 NFT 的权限 (卖方第一次发布作品时需要的操作)
    await erc1155.setApprovalForAll(proxy1, true, { from: account_a })

    // 获取 Atomiczer.atomicize 函数调用地址
    const abi = [{ 'constant': false, 'inputs': [{ 'name': 'addrs', 'type': 'address[]' }, { 'name': 'values', 'type': 'uint256[]' }, { 'name': 'calldataLengths', 'type': 'uint256[]' }, { 'name': 'calldatas', 'type': 'bytes' }], 'name': 'atomicize', 'outputs': [], 'payable': false, 'stateMutability': 'nonpayable', 'type': 'function' }]
    const atomicizerc = new web3.eth.Contract(abi, atomicizer.address)

    let tradingAmount = buyAmount * sellingPrice
    let commissionAmount = commission * tradingAmount
    let royaltyAmount = royalty * (tradingAmount - commissionAmount)
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
    const selectorOne = web3.eth.abi.encodeFunctionSignature('anyAddOne(bytes,address[7],uint8[2],uint256[6],bytes,bytes)')
    const selectorTwo = web3.eth.abi.encodeFunctionSignature('anyAddOne(bytes,address[7],uint8[2],uint256[6],bytes,bytes)')

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
      // 当前交易的份数
      maximumFill: sellingPrice * buyAmount,
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

    // 请求账户 A 进行签名确认
    let sigOne = await exchange.sign(one, account_a)
    // 签名确认
    let sigTwo = await exchange.sign(two, account_b)
    // 在账户 B 中为代理合约授予指定的转账金额权限 (买方第一次购买 NFT 时需要的操作)
    await erc20.approve(proxy2, totalMintAmount, { from: account_b })

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
    let [
      account_a_erc1155_balance,
      account_a_erc20_balance,
      account_b_erc20_balance,
      account_c_erc20_balance,
      account_d_erc20_balance,
      account_b_erc1155_balance
    ] = await Promise.all([
      erc1155.balanceOf(account_a, tokenId),
      erc20.balanceOf(account_a),
      erc20.balanceOf(account_b),
      erc20.balanceOf(account_c),
      erc20.balanceOf(account_d),
      erc1155.balanceOf(account_b, tokenId)
    ])

    console.log("account_a balance: %d, erc1155: %s", account_a_erc20_balance.toNumber(), account_a_erc1155_balance.toNumber())
    console.log("account_b balance: %d, erc1155: %s", account_b_erc20_balance.toNumber(), account_b_erc1155_balance.toNumber())
    console.log("account_c balance: %d", account_c_erc20_balance.toNumber())
    console.log("account_d balance: %d", account_d_erc20_balance.toNumber())

    assert.equal(account_a_erc20_balance.toNumber(), finalAmount, 'Incorrect ERC20 balance')
    assert.equal(account_b_erc1155_balance.toNumber(), buyAmount, 'Incorrect ERC1155 balance')
  }

  it('StaticMarket: matches erc1155 <> erc20 order, 1 fill', async () => {
    const price = 10000
    const mintAmount = 2

    return any_erc1155_for_erc20_test({
      tokenId: 5,               /* NFT TokenID */
      sellAmount: mintAmount,   /* 售卖份数 */
      sellingPrice: price,      /* 售卖的单份价格 */
      buyAmount: 1,             /* 买的份数 */
      account_a: accounts[0],   /* 卖方账户 */
      account_b: accounts[1],   /* 买方账户 */
      account_c: accounts[2],   /* 中间商 */
      account_d: accounts[3],   /* 作者账户 */
      royalty: 0.2,             /* 版税 */
      commission: 0.025,        /* 手续费 */
    })
  })
})