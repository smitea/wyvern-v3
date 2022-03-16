const WyvernAtomicizer = artifacts.require('WyvernAtomicizer')
const WyvernExchange = artifacts.require('WyvernExchange')
const WyvernStatic = artifacts.require('WyvernStatic')
const WyvernRegistry = artifacts.require('WyvernRegistry')
const TestERC20 = artifacts.require('TestERC20')
const TestERC721 = artifacts.require('TestERC721')
const TestERC1271 = artifacts.require('TestERC1271')
const TestERC1155 = artifacts.require('TestERC1155')

const { iteratee } = require('lodash')
const Web3 = require('web3')
const provider = new Web3.providers.HttpProvider('http://localhost:8545')
const web3 = new Web3(provider)

const {wrap,ZERO_BYTES32,CHAIN_ID,NULL_SIG,assertIsRejected} = require('./util')

contract('WyvernExchange', (accounts) =>{
    // Init
    let deploy_core_contracts = async () =>
    {
        let [registry,atomicizer] = await Promise.all([WyvernRegistry.new(), WyvernAtomicizer.new()])
        let [exchange,statici] = await Promise.all([WyvernExchange.new(CHAIN_ID,[registry.address],'0x'),WyvernStatic.new(atomicizer.address)])
        await registry.grantInitialAuthentication(exchange.address)
        return {registry,exchange:wrap(exchange),atomicizer,statici}
    }
    let deploy = async contracts => Promise.all(contracts.map(contract => contract.new()))

    it("ERC-1155 + ERC-20", async () =>{
        let account_a = accounts[0]
        let account_b = accounts[6]
        
        let price = 10000
        let tokenId = 4
        
        // 部署合约
        let {atomicizer, exchange, registry, statici} = await deploy_core_contracts()
        // 测试使用的 ERC20 和 ERC1155
        let [erc20,erc1155] = await deploy([TestERC20,TestERC1155])
        
        // 注册 A 代理
        await registry.registerProxy({from: account_a})
        // 获取 A 代理合约
        let proxy1 = await registry.proxies(account_a)
        assert.equal(true, proxy1.length > 0, 'no proxy address for account a')
    
        // 注册 B 代理
        await registry.registerProxy({from: account_b})
        // 获取 B 代理合约
        let proxy2 = await registry.proxies(account_b)
        assert.equal(true, proxy2.length > 0, 'no proxy address for account b')
        
        // 设置 NFT 所有权至 A & B 账户中
        await Promise.all([
            erc20.approve(proxy1,price,{from: account_a}),
            erc1155.setApprovalForAll(proxy1,true,{from: account_a}),
            erc1155.setApprovalForAll(proxy2,true,{from: account_b})
        ])
        await Promise.all([
            erc20.mint(account_a,price),
            erc1155.mint(account_a,tokenId,1),
            erc1155.mint(account_b,tokenId,1)]
        )
        
        const abi = [{'constant': false, 'inputs': [
            {'name': 'addrs', 'type': 'address[]'}, 
            {'name': 'values', 'type': 'uint256[]'}, 
            {'name': 'calldataLengths', 'type': 'uint256[]'}, 
            {'name': 'calldatas', 'type': 'bytes'}
        ], 'name': 'atomicize', 'outputs': [], 'payable': false, 'stateMutability': 'nonpayable', 'type': 'function'}]
        const atomicizerc = new web3.eth.Contract(abi, atomicizer.address)
        const erc20c = new web3.eth.Contract(erc20.abi, erc20.address)
        const erc1155c = new web3.eth.Contract(erc1155.abi, erc1155.address)
    
        // StaticUtil.split
        const selectorOne = web3.eth.abi.encodeFunctionSignature('split(bytes,address[7],uint8[2],uint256[6],bytes,bytes)')
        // StaticUtil.sequenceExact
        const selectorOneA = web3.eth.abi.encodeFunctionSignature('sequenceExact(bytes,address[7],uint8,uint256[6],bytes)')
        // StaticUtil.sequenceExact
        const selectorOneB = web3.eth.abi.encodeFunctionSignature('sequenceExact(bytes,address[7],uint8,uint256[6],bytes)')
        // StaticERC20.transferERC20Exact
        const firstEDSelector = web3.eth.abi.encodeFunctionSignature('transferERC20Exact(bytes,address[7],uint8,uint256[6],bytes)')
        const firstEDParams = web3.eth.abi.encodeParameters(['address', 'uint256'], [erc20.address, price])
        // StaticERC1155.sequenceExact
        const secondEDSelector = web3.eth.abi.encodeFunctionSignature('transferERC1155Exact(bytes,address[7],uint8,uint256[6],bytes)')
        const secondEDParams = web3.eth.abi.encodeParameters(['address', 'uint256', 'uint256'], [erc1155.address, tokenId, 1])
        const extradataOneA = web3.eth.abi.encodeParameters(
          ['address[]', 'uint256[]', 'bytes4[]', 'bytes'],
          [[statici.address, statici.address],
            [(firstEDParams.length - 2) / 2, (secondEDParams.length - 2) / 2],
            [firstEDSelector, secondEDSelector],
            firstEDParams + secondEDParams.slice(2)]
        )
        const bEDParams = web3.eth.abi.encodeParameters(['address', 'uint256', 'uint256'], [erc1155.address, tokenId, 1])
        const bEDSelector = web3.eth.abi.encodeFunctionSignature('transferERC1155Exact(bytes,address[7],uint8,uint256[6],bytes)')
        const extradataOneB = web3.eth.abi.encodeParameters(
          ['address[]', 'uint256[]', 'bytes4[]', 'bytes'],
          [[statici.address], [(bEDParams.length - 2) / 2], [bEDSelector], bEDParams]
        )
        const paramsOneA = web3.eth.abi.encodeParameters(
          ['address[2]', 'bytes4[2]', 'bytes', 'bytes'],
          [[statici.address, statici.address],
            [selectorOneA, selectorOneB],
            extradataOneA, extradataOneB]
        )
        const extradataOne = paramsOneA
        const selectorTwo = web3.eth.abi.encodeFunctionSignature('any(bytes,address[7],uint8[2],uint256[6],bytes,bytes)')
        const extradataTwo = '0x'
        const one = {registry: registry.address, maker: account_a, staticTarget: statici.address, staticSelector: selectorOne, staticExtradata: extradataOne, maximumFill: '1', listingTime: '0', expirationTime: '10000000000', salt: '3352'}
        const two = {registry: registry.address, maker: account_b, staticTarget: statici.address, staticSelector: selectorTwo, staticExtradata: extradataTwo, maximumFill: '1', listingTime: '0', expirationTime: '10000000000', salt: '3335'}
        const sig = NULL_SIG
        const firstERC20Call = erc20c.methods.transferFrom(account_a, account_b, price).encodeABI()
        const firstERC1155Call = erc1155c.methods.safeTransferFrom(account_a, account_b, tokenId, 1, "0x").encodeABI() + ZERO_BYTES32.substr(2)

        console.log("firstERC20Call: %s, len: %d", firstERC20Call, (firstERC20Call.length - 2) / 2)
        console.log("firstERC1155Call: %s, len: %d", firstERC1155Call, (firstERC1155Call.length - 2) / 2)
        console.log("calldata: %s", firstERC20Call + firstERC1155Call.slice(2))

        const firstData = atomicizerc.methods.atomicize(
          [erc20.address, erc1155.address],
          [0, 0],
          [(firstERC20Call.length - 2) / 2, (firstERC1155Call.length - 2) / 2],
          firstERC20Call + firstERC1155Call.slice(2)
        ).encodeABI()

        console.log("firstData: %s", firstData)
        
        const secondERC1155Call = erc1155c.methods.safeTransferFrom(account_b, account_a, tokenId, 1, "0x").encodeABI() + ZERO_BYTES32.substr(2)
        const secondData = atomicizerc.methods.atomicize(
          [erc1155.address],
          [0],
          [(secondERC1155Call.length - 2) / 2],
          secondERC1155Call
        ).encodeABI()
            
        const firstCall = {target: atomicizer.address, howToCall: 1, data: firstData}
        const secondCall = {target: atomicizer.address, howToCall: 1, data: secondData}
        
        let twoSig = await exchange.sign(two, account_b)
        await exchange.atomicMatch(one, sig, firstCall, two, twoSig, secondCall, ZERO_BYTES32)
        let [new_balance1,new_balance2] = await Promise.all([erc1155.balanceOf(account_a, tokenId),erc1155.balanceOf(account_b, tokenId)])
        assert.isTrue(new_balance1.toNumber() > 0,'Incorrect balance')
        assert.isTrue(new_balance2.toNumber() > 0,'Incorrect balance')
        assert.equal(await erc20.balanceOf(account_b), price, 'Incorrect balance')
    })
})