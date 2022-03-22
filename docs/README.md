# Wyvern Protocol

Project Wyvern is a decentralized digital asset exchange protocol running on Ethereum. Buy and sell everything from virtual kittens to smart contracts with no counterparty risk.

## 架构设计

### 模块设计

Wyvern Protocol 按照数据和业务逻辑分离的原则进行设计， 其中数据部分仅在 `Registry` 合约中实现，而协议验证和流程控制的业务逻辑在 `Exchange` 中实现

![Wyvern Module](images/Wyvern%20Protocol01.png)

## 交易过程

### 上架
1. `Register` 创建账户代理
2. `ApprovalForAll` 为账户代理授予 ERC1155 NFT 转账的权限

### 下架

### 降价

### 购买
1. `sign` 交易双方需要签名确认
2. `atomicMatchWith` 进行交易

![Wyvern Module](images/Wyvern%20Protocol02.png)

## 相关 EIP

- [EIP-20](https://eips.ethereum.org/EIPS/eip-20) 交易合约
- [EIP-712](https://segmentfault.com/a/1190000015647458) 签名合约
- [EIP-897](https://eips.ethereum.org/EIPS/eip-897) 代理合约
- [EIP-1155](https://zhuanlan.zhihu.com/p/389331603) 资产合约
- [EIP-1271](https://support.opensea.io/hc/zh-tw/articles/4449355421075-%E6%99%BA%E8%83%BD%E5%90%88%E7%B4%84%E5%8D%87%E7%B4%9A-%E7%B0%BD%E5%90%8D%E8%AB%8B%E6%B1%82%E6%98%AF%E4%BB%80%E9%BA%BC%E6%A8%A3%E7%9A%84-) 在 712 合约的基础上修改的合约

## 协议描述

### Asserting registry

The order maker may check that they and their counterparty are using valid registries (though registries are also whitelisted in the Exchange contract).

> 交易双方都需要登记在注册表中，该注册表维护了所有的交易代理合约

- 用户发布作品时，需要创建一个 `ProxyRegistry` 合约
- 检查 `ProxyRegistry` 的合约地址是否已被注册(无论该地址是否在白名单中),如果没有，则表示该用户还未部署 `ProxyRegistry`

### Asserting calldata

The bulk of the logic in an order is in constructing the predicate over the call and countercall. Each order's static callback (predicate function) receives all parameters of the call, counterparty call, and order metadata (Ether value, timestamp, matching address) and must decide whether to allow the order to match, and if so how much to fill it.

- `atomicMatch_` 中提供了大部分的静态回调地址作为参数，比如(订单数据，代理的注册器合约地址，代理的创建者地址以及其他支付代码块数据)，并且要在回调的代码块中实现如何处理订单和其 fill 值

``` solidity
/* An order, convenience struct. */
struct Order {
    /* Order registry address. */
    address registry;
    /* Order maker address. */
    address maker;
    /* Order static target. */
    address staticTarget;
    /* Order static selector. */
    bytes4 staticSelector;
    /* Order static extradata. */
    bytes staticExtradata;
    /* Order maximum fill factor. */
    uint256 maximumFill;
    /* Order listing timestamp. */
    uint256 listingTime;
    /* Order expiration timestamp - 0 for no expiry. */
    uint256 expirationTime;
    /* Order salt to prevent duplicate hashes. */
    uint256 salt;
}
```

> 订单元数据中大部分都是用来验证交易规则，其中部分静态回调地址，比如 `target` `selector` `extradata` 属性表示如何处理该订单的 fill 值， listingTime 和 expirationTime 用于保证该订单的有效时间范围外不会发生交易活动。

### Call

The first call is executed by the maker of the order through their proxy contract. The static callback receives all parameters - the call target, the call type (CALL or DELEGATECALL), and the call data - and must validate that the call is one which the maker is willing to perform (e.g. transferring a particular asset or set of assets).

> 第一次调用由通过卖方的代理合约执行。 静态回调参数提供了 `Call` 结构: 调用目标、调用类型、执行的代码块, 并且必须验证该次调用是卖方许可的(比如转移特定资产或者一组资产)

### Countercall

The second call is executed by the counterparty and referred to in the source as the "countercall" for convenience. The static callback receives all parameters - the countercall target, the countercall type (CALL or DELEGATECALL), and the countercall data - and must validate that the call is one which the maker is willing to accept in return for their own (e.g. transferring a particular asset or set of assets).

> 第二次调用由买方执行，为方便起见，在代码中将其称为 `countercall`。 静态回调接收所有参数 `countercall target`、`countercall type (CALL or DELEGATECALL)`和 `countercall data`, 并且必须验证 call 是卖方许可的调用（例如 transferring 特定的资产或一组资产）。

### Asserting state

Static calls are executed after the calls (the whole transaction is reverted if the static call fails), so instead of asserting properties of the calldata, you can assert that particular state has changed - e.g. that an account now owns some asset. In some cases this may be more efficient, but it is trickier to reason through and could lead to unintentional consequences if the state changed for other reasons (for example, if the asset you were trying to buy were gifted to you) - so this is recommended for special cases only, such as placing a bug bounty on a contract if an invariant is violated.

> 订单的中的 静态回调函数会在最后执行，如果执行失败，则会将整个交易活动事务回滚。

### Metadata

Metadata contains order listing time, order expiration time, counterorder listing time, Ether passed in the call (if any), current order fill value, and the matching address.

> 元数据包含订单上架时间、订单到期时间、以太币（如果有）、当前订单成交量。

### Generalized Partial Fill

Orders sign over a maximum fill, and static calls return a uint, which specifies the updated fill value if the order is matched. The current fill of an order can also be manually set by the maker of the order with a transaction (this also allows for order cancellation). Note that setting the fill of an order to a nonzero value also implicitly authorizes the order, since authorization of partially filled orders is cached to avoid unnecessary signature checks.

> 订单签署最大成交，静态调用返回一个 uint，如果订单匹配，它指定更新的成交值。 订单的当前执行也可以由订单的制造者通过交易手动设置（这也允许订单取消）。 请注意，将订单的成交设置为非零值也会隐式授权订单，因为部分成交订单的授权被缓存以避免不必要的签名检查。

### Authorizing an order

Orders must always be authorized by the maker address, who owns the proxy contract which will perform the call. Authorization can be done in three ways: by signed message, by pre-approval, and by match-time approval.

> 订单必须始终卖方地址授权，卖方地址拥有将执行调用的代理合约。 授权可以通过三种方式完成：签名消息、预先批准和指定时间批准。

#### Signed message

The most common method of authorizing an order is to sign the order hash off-chain. This is costless - any number of orders can be signed, stored, indexed, and perhaps listed on a website or automated orderbook. To avoid the necessity of cancelling no-longer-desired orders, makers can sign orders with expiration times in the near future and re-sign new orders for only as long as they wish to continue soliciting the trade.

> 授权订单的最常见方法是在链下对订单哈希进行签名。 这是零成本的——任何数量的订单都可以被签名、存储、索引，也许还可以在网站或自动订单簿上列出。 为了避免取消不再需要的订单的必要性，制造商可以在不久的将来签署具有到期时间的订单，并且只要他们希望继续征求交易，就可以重新签署新订单。

#### Pre-approval

Alternatively, an order can be authorized by sending a transaction to the WyvernExchange contract. This method may be of particular interest for orders constructed by smart contracts, which cannot themselves sign messages off-chain. On-chain authorization emits an event which can be easily indexed by orderbooks who may wish to include the order in their database.

> 或者，可以通过向 WyvernExchange 合约发送交易来授权订单。 这种方法可能对由智能合约构建的订单特别感兴趣，智能合约本身不能在链下签署消息。 链上授权会发出一个事件，该事件可以很容易地被希望将订单包含在其数据库中的订单簿索引。

#### Match-time approval

Finally, an order can be constructed on the fly (likely to match an existing previously signed or approved order) and authorized at match time simply by sending the match transaction from the order's maker address. If the maker intends to send the transaction matching the order themselves, this method may be convenient, and it can be used to save a bit of gas (since calldata verification is implied by sending the transaction).

> 最后，可以即时构建订单（可能匹配现有的先前签署或批准的订单）并在匹配时通过从订单的制造商地址发送匹配交易来授权。 如果 maker 打算自己发送与订单匹配的交易，这种方法可能会很方便，并且可以节省一点 gas（因为发送交易隐含了 calldata 验证）。

### Matching orders

#### Constructing matching calldata

Matching calldata can be constructed in any fashion off-chain. The protocol does not care how the final calldata is obtained, only that it fulfills the orders' predicate functions. In practice, orderbook maintainers (relayers) will likely store additional metadata along with orders which can be used to construct possible matching calldatas.

> 匹配的调用数据可以以任何方式链下构建。 协议并不关心最终的 calldata 是如何获得的，只关心它完成了订单的谓词功能。 在实践中，订单簿维护者（中继者）可能会存储额外的元数据以及订单，这些订单可用于构建可能的匹配调用数据。

#### Asymmetries

To the extent possible, the protocol is designed to be symmetric, such that orders need not be on any particular "side" and restrict themselves to matching with orders on the other "side".

> 在可能的范围内，该协议被设计为对称的。

#### Call ordering

The first asymmetry is ordering. One call must be executed first, and executing that call might change the result of the second call. The first call passed into atomicMatch is executed first.

> 第一个不对称是排序。 必须首先执行一个调用，执行该调用可能会更改第二个调用的结果。 传递给 atomicMatch 的第一个调用首先执行。

#### Special-cased Ether

The second asymmetry is special-cased Ether. Due to Ethereum design limitations, Ether is a wired-in asset (unlike ERC20 tokens) which can only be sent from an account by a transaction from said account. To facilitate ease-of-use, Wyvern supports special-case Ether to the maximum extent possible: the matcher of an order may elect to pass value along with the match transaction, which is then transferred to the counterparty and passed as a parameter to the predicate function (which can assert e.g. that a particular amount was sent).

> 第二个不对称是特殊情况下的以太币。 由于以太坊的设计限制，以太币是一种有线资产（与 ERC20 代币不同），只能通过来自该账户的交易从一个账户发送。 为了便于使用，Wyvern 尽可能支持特殊情况的 Ether：订单的匹配者可以选择将价值与匹配交易一起传递，然后将其传递给交易对手并作为参数传递给 谓词函数（可以断言例如已发送特定数量）。

#### Self-matching

Orders cannot be self-matched; however, two separate orders from the same maker can be matched with each other.

> 訂單不能自行匹配；但是，來自同一製造商的兩個單獨的訂單可以相互匹配。

```solidity
/* Prevent self-matching (possibly unnecessary, but safer). (保证这是两笔独立的订单) */
require(firstHash != secondHash, "Self-matching orders is prohibited");
```
