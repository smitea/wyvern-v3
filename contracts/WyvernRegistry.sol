pragma solidity 0.7.5;

import "./registry/ProxyRegistry.sol";
import "./registry/AuthenticatedProxy.sol";

/**
 * @title WyvernRegistry
 * @author Wyvern Protocol Developers
 */
contract WyvernRegistry is ProxyRegistry {
    string public constant name = "Wyvern Protocol Proxy Registry";

    /* Whether the initial auth address has been set. */
    bool public initialAddressSet = false;

    constructor() public {
        AuthenticatedProxy impl = new AuthenticatedProxy();
        // 为合约代理初始化一个注册器地址
        impl.initialize(address(this), this);
        // 授予可被注销的权限
        impl.setRevoke(true);
        // 设置代理的地址
        delegateProxyImplementation = address(impl);
    }

    /**
     * Grant authentication to the initial Exchange protocol contract
     *
     * @dev No delay, can only be called once - after that the standard registry process with a delay must be used
     * @param authAddress Address of the contract to grant authentication
     */
    function grantInitialAuthentication(address authAddress) public onlyOwner {
        require(
            !initialAddressSet,
            "Wyvern Protocol Proxy Registry initial address already set"
        );
        initialAddressSet = true;
        contracts[authAddress] = true;
    }
}
