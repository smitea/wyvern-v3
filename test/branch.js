const WyvernAtomicizer = artifacts.require('WyvernAtomicizer')
const WyvernExchange = artifacts.require('WyvernExchange')
const WyvernStatic = artifacts.require('WyvernStatic')
const WyvernRegistry = artifacts.require('WyvernRegistry')
const TestERC20 = artifacts.require('TestERC20')
const TestERC721 = artifacts.require('TestERC721')
const TestERC1271 = artifacts.require('TestERC1271')
const TestERC1155 = artifacts.require('TestERC1155')
const StaticMarket = artifacts.require('./StaticMarket.sol')

const { iteratee } = require('lodash')
const Web3 = require('web3')
const provider = new Web3.providers.HttpProvider('http://localhost:8545')
const web3 = new Web3(provider)

const { wrap, ZERO_BYTES32, CHAIN_ID, NULL_SIG, assertIsRejected } = require('./util')

contract('WyvernExchange', (accounts) => {
  // Init
  let deploy_core_contracts = async () => {
    let [registry, atomicizer] = await Promise.all([WyvernRegistry.new(), WyvernAtomicizer.new()])
    let [exchange, statici] = await Promise.all([WyvernExchange.new(CHAIN_ID, [registry.address], '0x'), StaticMarket.new()])
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
    let { exchange, registry, statici } = await deploy_core_contracts()
    let [erc20, erc1155] = await deploy([TestERC20, TestERC1155])

    // 注册代理合约，初始化钱包时需要签约代理 (卖方第一次发布作品时需要的操作)
    await registry.registerProxy({ from: account_a })
    let proxy1 = await registry.proxies(account_a)
    assert.equal(true, proxy1.length > 0, 'no proxy address for account a')

    await registry.registerProxy({ from: account_b })
    let proxy2 = await registry.proxies(account_b)
    assert.equal(true, proxy2.length > 0, 'no proxy address for account b')

    let totalMintAmount = buyAmount * sellingPrice + 1
    // 在账户 B 中为代理合约授予指定的转账金额权限 (买方第一次购买 NFT 时需要的操作)
    await erc20.approve(proxy2, totalMintAmount, { from: account_b })
    // 为账户 B 铸造一些的代币 (测试步骤)
    await erc20.mint(account_b, totalMintAmount)

    // 在账户 A 中为代理合约授予允许转走 NFT 的权限 (卖方第一次发布作品时需要的操作)
    await erc1155.setApprovalForAll(proxy1, true, { from: account_a })
    // 为账户 A 铸造指定的 NFT 数量 (测试步骤)
    await erc1155.mint(account_a, tokenId, sellAmount)

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
    const selectorOne = web3.eth.abi.encodeFunctionSignature('anyERC1155ForERC20(bytes,address[7],uint8[2],uint256[6],bytes,bytes)')
    const selectorTwo = web3.eth.abi.encodeFunctionSignature('anyERC20ForERC1155(bytes,address[7],uint8[2],uint256[6],bytes,bytes)')

    // 设置订单处理时所需的参数
    const paramsOne = web3.eth.abi.encodeParameters(
      ['address[2]', 'uint256[3]'],
      [[erc1155.address, erc20.address], [tokenId, buyAmount, sellingPrice]]
    )
    const paramsTwo = web3.eth.abi.encodeParameters(
      ['address[2]', 'uint256[3]'],
      [[erc20.address, erc1155.address], [tokenId, sellingPrice, buyAmount]]
    )

    const one = {
      registry: registry.address,
      maker: account_a,
      staticTarget: statici.address,
      staticSelector: selectorOne,
      staticExtradata: paramsOne,
      maximumFill: sellAmount,
      listingTime: '0',
      expirationTime: '10000000000',
      salt: '11'
    }
    const two = {
      registry: registry.address,
      maker: account_b,
      staticTarget: statici.address,
      staticSelector: selectorTwo,
      staticExtradata: paramsTwo,
      maximumFill: sellingPrice * buyAmount,
      listingTime: '0',
      expirationTime: '10000000000',
      salt: '12'
    }

    console.log("order01: %s", one)
    console.log("order02: %s", two)

    // (NFT 转让) A 账户转让 1 * NFT => B 账户
    const firstData = erc1155c.methods.safeTransferFrom(
      account_a,
      account_b,
      tokenId,
      buyAmount,
      "0x"
    ).encodeABI() + ZERO_BYTES32.substr(2)
    console.log("erc1155.safeTransferFrom(%s, %s, %d, %d, %s)", account_a, account_b, tokenId, buyAmount, "0x")

    // (交易金额转账) B 账户转让 1 * 10000 * 0.75 代币 => A 账户
    const secondData = erc20c.methods.transferFrom(
      account_b,
      account_a,
      finalAmount
    ).encodeABI()
    console.log("erc20.transferFrom(%s, %s, %d)", account_a, account_b, finalAmount)

    // (手续费转帐) B 账户转让 1 * 10000 代币 => C 账户
    const thirdData = erc20c.methods.transferFrom(
      account_b,
      account_a,
      commissionAmount
    ).encodeABI()
    console.log("erc20.transferFrom(%s, %s, %d)", account_c, account_b, commissionAmount)

    // (版税转账) B 账户转让 1 * 10000 代币 => D 账户
    const fourthData = erc20c.methods.transferFrom(
      account_b,
      account_a,
      commissionAmount
    ).encodeABI()
    console.log("erc20.transferFrom(%s, %s, %d)", account_d, account_b, royaltyAmount)

    const firstCall = { target: erc1155.address, howToCall: 0, data: firstData }
    const secondCall = { target: erc20.address, howToCall: 0, data: secondData }
    const thirdCall = { target: erc20.address, howToCall: 0, data: thirdData }
    const fourthCall = { target: erc20.address, howToCall: 0, data: fourthData }

    // 签名确认
    let sigOne = await exchange.sign(one, account_a)
    let sigTwo = await exchange.sign(two, account_b)

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
    let [account_a_erc20_balance, account_b_erc1155_balance] = await Promise.all([erc20.balanceOf(account_a), erc1155.balanceOf(account_b, tokenId)])
    assert.equal(account_a_erc20_balance.toNumber(), sellingPrice * buyAmount * txCount, 'Incorrect ERC20 balance')
    assert.equal(account_b_erc1155_balance.toNumber(), sellingNumerator || (buyAmount * txCount), 'Incorrect ERC1155 balance')
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
      royalty: 0.4,             /* 版税 */
      commission: 0.25,         /* 手续费 */
    })
  })
})