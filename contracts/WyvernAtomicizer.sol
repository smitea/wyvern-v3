/*

  << Wyvern Atomicizer >>

  Execute multiple transactions, in order, atomically (if any fails, all revert).

*/

pragma solidity 0.7.5;

/**
 * @title WyvernAtomicizer
 * @author Wyvern Protocol Developers
 */
library WyvernAtomicizer {

    function atomicize(
        address[] calldata addrs,
        uint256[] calldata values,
        uint256[] calldata calldataLengths,
        bytes calldata calldatas
    ) external {
        // addrs (合约的调用地址列表)
        // values (无))
        // calldataLengths(回调代码块长度 - 2 / 2)
        // calldatas(回调代码块)

        // 校验参数的列表长度是否相等
        require(
            addrs.length == values.length &&
                addrs.length == calldataLengths.length,
            "Addresses, calldata lengths, and values must match in quantity"
        );

        uint256 j = 0;
        for (uint256 i = 0; i < addrs.length; i++) {
            bytes memory cd = new bytes(calldataLengths[i]);
            for (uint256 k = 0; k < calldataLengths[i]; k++) {
                cd[k] = calldatas[j];
                j++;
            }
            (bool success, ) = addrs[i].call{value: values[i]}(cd);
            require(success, "Atomicizer subcall failed");
        }
    }
}