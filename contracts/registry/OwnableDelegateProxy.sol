pragma solidity 0.7.5;

import "./proxy/OwnedUpgradeabilityProxy.sol";

/**
 * @title OwnableDelegateProxy
 * @author Wyvern Protocol Developers
 */
contract OwnableDelegateProxy is OwnedUpgradeabilityProxy {
    constructor(
        address owner,
        address initialImplementation,
        bytes memory data
    ) public {
        // 设置代理的所有者(作者)
        setUpgradeabilityOwner(owner);
        // 更新代理合约实现的地址
        _upgradeTo(initialImplementation);
        // 执行内部调用(不产生合约调用记录)
        (bool success, ) = initialImplementation.delegatecall(data);
        require(success, "OwnableDelegateProxy failed implementation");
    }
}
