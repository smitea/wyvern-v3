# Wyvern Protocol

## 交易過程

可以借鑑 Opensea 官方的買賣流程來進行參考

### 販賣

1. 每個新帳戶第一次發布作品時，需要進行初始化錢包操作： 通過調用 `createdProxy` 在鏈上創建一個合約，即代理合約，對應的就是 `WyvernRegistry`
2. 授權允許 `WyvernRegistry`合約將 NTF 所有者的資產轉移：通過調用 `setApprovalForAll` 來進行
3. 簽名認證，確保當前操作屬於本人操作

### 購買

主要使用協議中 `atomicMatch` 函數: 
1. 轉帳該筆金額的 97.5% 給NFT 原擁有者
2. 轉帳該筆金額的 2.5% 給 OpenSea
3. 通過 proxy 合約，調用 NFT 合約的 `transferFrom`，轉移 NFT

## 相關 EIP

- [EIP-20](https://eips.ethereum.org/EIPS/eip-20)
- [EIP-712](https://segmentfault.com/a/1190000015647458)
- [EIP-721](https://learnblockchain.cn/docs/eips/eip-721.html)
- [EIP-897](https://eips.ethereum.org/EIPS/eip-897)
- [EIP-1155](https://zhuanlan.zhihu.com/p/389331603)
- [EIP-1271](https://support.opensea.io/hc/zh-tw/articles/4449355421075-%E6%99%BA%E8%83%BD%E5%90%88%E7%B4%84%E5%8D%87%E7%B4%9A-%E7%B0%BD%E5%90%8D%E8%AB%8B%E6%B1%82%E6%98%AF%E4%BB%80%E9%BA%BC%E6%A8%A3%E7%9A%84-) 

## 協議描述

### Asserting registry

The order maker may check that they and their counterparty are using valid registries (though registries are also whitelisted in the Exchange contract).

> 檢查 `ProxyRegistry` 的合約地址是否已被註冊(無論該地址是否在白名單中)，如果沒有，則表示該用戶還未部署 `ProxyRegistry`

### Asserting calldata

The bulk of the logic in an order is in constructing the predicate over the call and countercall. Each order's static callback (predicate function) receives all parameters of the call, counterparty call, and order metadata (Ether value, timestamp, matching address) and must decide whether to allow the order to match, and if so how much to fill it.

> 
> 訂單中的大部分邏輯是在調用和反調用上構造謂詞。每個訂單的靜態回調（謂詞函數）接收調用、交易對手調用和訂單元數據（以太幣值、時間戳、匹配地址）的所有參數，並且必須決定是否允許訂單匹配，如果允許，填寫多少。

### Call

The first call is executed by the maker of the order through their proxy contract. The static callback receives all parameters - the call target, the call type (CALL or DELEGATECALL), and the call data - and must validate that the call is one which the maker is willing to perform (e.g. transferring a particular asset or set of assets).

> 第一次調用由訂單製造者通過他們的代理合約執行。靜態回調接收所有參數——調用目標、調用類型（或）和調用數據——並且必須驗證調用是製造商願意執行的調用（例如轉移特定資產或一組資產）。CALLDELEGATECALL

### Countercall

The second call is executed by the counterparty and referred to in the source as the "countercall" for convenience. The static callback receives all parameters - the countercall target, the countercall type (CALL or DELEGATECALL), and the countercall data - and must validate that the call is one which the maker is willing to accept in return for their own (e.g. transferring a particular asset or set of assets).

> 第二次調用由交易對手執行，為方便起見，在源代碼中將其稱為“countercall”。靜態回調接收所有參數 - countercall 目標、countercall 類型（或）和 countercall 數據 - 並且必須驗證調用是製造商願意接受以換取他們自己的調用（例如轉移特定資產或資產集）。CALLDELEGATECALL

### Asserting state

Static calls are executed after the calls (the whole transaction is reverted if the static call fails), so instead of asserting properties of the calldata, you can assert that particular state has changed - e.g. that an account now owns some asset. In some cases this may be more efficient, but it is trickier to reason through and could lead to unintentional consequences if the state changed for other reasons (for example, if the asset you were trying to buy were gifted to you) - so this is recommended for special cases only, such as placing a bug bounty on a contract if an invariant is violated.

> 靜態調用在調用之後執行（如果靜態調用失敗，整個事務將被恢復），因此您可以斷言特定狀態已更改，而不是斷言調用數據的屬性 - 例如，一個帳戶現在擁有一些資產。在某些情況下，這可能更有效，但推理起來更棘手，並且如果狀態因其他原因而改變（例如，如果您嘗試購買的資產被贈送給您）可能會導致意外後果 - 所以這是僅推薦用於特殊情況，例如如果違反不變量，則在合同上放置錯誤賞金。

### Metadata

Metadata contains order listing time, order expiration time, counterorder listing time, Ether passed in the call (if any), current order fill value, and the matching address.

> 元數據包含掛單時間、掛單到期時間、反掛單掛單時間、調用中傳入的以太幣（如果有）、當前訂單成交值和匹配地址。

### Generalized Partial Fill

Orders sign over a maximum fill, and static calls return a uint, which specifies the updated fill value if the order is matched. The current fill of an order can also be manually set by the maker of the order with a transaction (this also allows for order cancellation). Note that setting the fill of an order to a nonzero value also implicitly authorizes the order, since authorization of partially filled orders is cached to avoid unnecessary signature checks.

> 訂單簽署最大成交，靜態調用返回一個 uint，如果訂單匹配，它指定更新的成交值。訂單的當前執行也可以由訂單的製造者通過交易手動設置（這也允許訂單取消）。請注意，將訂單的成交設置為非零值也會隱式授權訂單，因為部分成交訂單的授權被緩存以避免不必要的簽名檢查。

### Authorizing an order

Orders must always be authorized by the maker address, who owns the proxy contract which will perform the call. Authorization can be done in three ways: by signed message, by pre-approval, and by match-time approval.

> 訂單必須始終由地址授權，該地址擁有將執行調用的代理合約。授權可以通過三種方式完成：簽名消息、預先批准和匹配時間批准。

#### Signed message

The most common method of authorizing an order is to sign the order hash off-chain. This is costless - any number of orders can be signed, stored, indexed, and perhaps listed on a website or automated orderbook. To avoid the necessity of cancelling no-longer-desired orders, makers can sign orders with expiration times in the near future and re-sign new orders for only as long as they wish to continue soliciting the trade.

> 授權訂單的最常見方法是在鏈下對訂單哈希進行簽名。這是無成本的——任何數量的訂單都可以被簽名、存儲、索引，也許還可以在網站或自動訂單簿上列出。為了避免取消不再需要的訂單的必要性，製造商可以在不久的將來簽署具有到期時間的訂單，並且只要他們希望繼續徵求交易，就可以重新簽署新訂單。

#### Pre-approval

Alternatively, an order can be authorized by sending a transaction to the WyvernExchange contract. This method may be of particular interest for orders constructed by smart contracts, which cannot themselves sign messages off-chain. On-chain authorization emits an event which can be easily indexed by orderbooks who may wish to include the order in their database.

> 或者，可以通過向合約發送交易來授權訂單。這種方法可能對由智能合約構建的訂單特別感興趣，智能合約本身不能在鏈下簽署消息。鏈上授權會發出一個事件，該事件可以很容易地被希望將訂單包含在其數據庫中的訂單簿索引。WyvernExchange

#### Match-time approval

Finally, an order can be constructed on the fly (likely to match an existing previously signed or approved order) and authorized at match time simply by sending the match transaction from the order's maker address. If the maker intends to send the transaction matching the order themselves, this method may be convenient, and it can be used to save a bit of gas (since calldata verification is implied by sending the transaction).

> 最後，可以即時構建訂單（可能匹配現有的先前簽署或批准的訂單）並在匹配時通過從訂單地址發送匹配交易進行授權。如果 maker 打算自己發送與訂單匹配的交易，這種方法可能會很方便，並且可以節省一點 gas（因為發送交易隱含了 calldata 驗證）。maker

### Matching orders

#### Constructing matching calldata

Matching calldata can be constructed in any fashion off-chain. The protocol does not care how the final calldata is obtained, only that it fulfills the orders' predicate functions. In practice, orderbook maintainers (relayers) will likely store additional metadata along with orders which can be used to construct possible matching calldatas.

> 匹配的調用數據可以以任何方式鏈下構建。該協議不關心最終的 calldata 是如何獲得的，只關心它完成了訂單的謂詞功能。在實踐中，訂單簿維護者（中繼者）可能會存儲額外的元數據以及訂單，這些訂單可用於構建可能的匹配調用數據。

#### Asymmetries

To the extent possible, the protocol is designed to be symmetric, such that orders need not be on any particular "side" and restrict themselves to matching with orders on the other "side".

> 在可能的範圍內，該協議被設計成對稱的，這樣訂單不需要在任何特定的“邊”上，並且限制自己與另一“邊”上的訂單匹配。

#### Call ordering

The first asymmetry is ordering. One call must be executed first, and executing that call might change the result of the second call. The first call passed into atomicMatch is executed first.

> 第一個不對稱是排序。必須首先執行一個調用，執行該調用可能會更改第二個調用的結果。傳入的第一個調用首先執行。atomicMatch

#### Special-cased Ether

The second asymmetry is special-cased Ether. Due to Ethereum design limitations, Ether is a wired-in asset (unlike ERC20 tokens) which can only be sent from an account by a transaction from said account. To facilitate ease-of-use, Wyvern supports special-case Ether to the maximum extent possible: the matcher of an order may elect to pass value along with the match transaction, which is then transferred to the counterparty and passed as a parameter to the predicate function (which can assert e.g. that a particular amount was sent).

> 第二個不對稱是特殊情況下的以太幣。由於以太坊的設計限制，以太幣是一種有線資產（與 ERC20 代幣不同），只能通過來自該賬戶的交易從該賬戶發送。為了便於使用，Wyvern 盡可能支持特殊情況的 Ether：訂單的匹配者可以選擇將價值與匹配交易一起傳遞，然後將其傳遞給交易對手並作為參數傳遞給謂詞函數（可以斷言例如已發送特定數量）。

#### Self-matching

Orders cannot be self-matched; however, two separate orders from the same maker can be matched with each other.

> 訂單不能自行匹配；但是，來自同一製造商的兩個單獨的訂單可以相互匹配。