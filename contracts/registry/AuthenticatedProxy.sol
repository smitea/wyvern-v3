pragma solidity 0.7.5;

import "./ProxyRegistry.sol";
import "./TokenRecipient.sol";
import "./proxy/OwnedUpgradeabilityStorage.sol";

/**
 * @title AuthenticatedProxy
 * @author Wyvern Protocol Developers
 * @dev Proxy contract to hold access to assets on behalf of a user (e.g. ERC20 approve) and execute calls under particular conditions.
 */
contract AuthenticatedProxy is TokenRecipient, OwnedUpgradeabilityStorage {
    /* Whether initialized. (当前初始化状态) */
    bool initialized = false;

    /* Address which owns this proxy. (当前代理的用户地址<卖家>) */
    address public user;

    /* Associated registry with contract authentication information. (当前代理使用的注册器) */
    ProxyRegistry public registry;

    /* Whether access has been revoked. (是否有注销权限) */
    bool public revoked;

    /* Delegate call could be used to atomically transfer multiple assets owned by the proxy contract with one order. */
    enum HowToCall {
        Call,
        DelegateCall
    }

    /* Event fired when the proxy access is revoked or unrevoked. */
    event Revoked(bool revoked);

    /**
     * Initialize an AuthenticatedProxy (初始化一个授权代理)
     *
     * @param addrUser Address of user on whose behalf this proxy will act (当前代理的用户地址)
     * @param addrRegistry Address of ProxyRegistry contract which will manage this proxy (ProxyRegistry 合约地址，用于管理该代理的注册器地址)
     */
    function initialize(address addrUser, ProxyRegistry addrRegistry) public {
        // 必须没有初始化过
        require(!initialized, "Authenticated proxy already initialized");
        initialized = true;
        user = addrUser;
        registry = addrRegistry;
    }

    /**
     * Set the revoked flag (allows a user to revoke ProxyRegistry access)
     *
     * @dev Can be called by the user only
     * @param revoke Whether or not to revoke access
     */
    function setRevoke(bool revoke) public {
        require(
            msg.sender == user,
            "Authenticated proxy can only be revoked by its user"
        );
        revoked = revoke;
        emit Revoked(revoke);
    }

    /**
     * Execute a message call from the proxy contract
     *
     * @dev Can be called by the user, or by a contract authorized by the registry as long as the user has not revoked access
     * @param dest Address to which the call will be sent
     * @param howToCall Which kind of call to make
     * @param data Calldata to send
     * @return result Result of the call (success or failure)
     */
    function proxy(
        address dest,
        HowToCall howToCall,
        bytes memory data
    ) public returns (bool result) {
        require(
            msg.sender == user || (!revoked && registry.contracts(msg.sender)),
            "Authenticated proxy can only be called by its user, or by a contract authorized by the registry as long as the user has not revoked access"
        );
        bytes memory ret;
        if (howToCall == HowToCall.Call) {
            (result, ret) = dest.call(data);
        } else if (howToCall == HowToCall.DelegateCall) {
            (result, ret) = dest.delegatecall(data);
        }
        return result;
    }

    /**
     * Execute a message call and assert success
     *
     * @dev Same functionality as `proxy`, just asserts the return value
     * @param dest Address to which the call will be sent
     * @param howToCall What kind of call to make
     * @param data Calldata to send
     */
    function proxyAssert(
        address dest,
        HowToCall howToCall,
        bytes memory data
    ) public {
        require(proxy(dest, howToCall, data), "Proxy assertion failed");
    }
}
