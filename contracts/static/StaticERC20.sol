/*

    StaticERC20 - static calls for ERC20 trades

*/

pragma solidity 0.7.5;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "../lib/ArrayUtils.sol";
import "../registry/AuthenticatedProxy.sol";

contract StaticERC20 {
    function transferERC20Exact(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall howToCall,
        uint256[6] memory,
        bytes memory data
    ) public pure {
        // Decode extradata
        (address token, uint256 amount) = abi.decode(extra, (address, uint256));

        // Call target = token to give
        require(addresses[2] == token, "Call target = token to give");
        // Call type = call
        require(howToCall == AuthenticatedProxy.HowToCall.Call,"Call type = call");
        // Assert calldata
        require(
            ArrayUtils.arrayEq(
                data,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    addresses[1],
                    addresses[4],
                    amount
                )
            ),
            "Assert calldata"
        );
    }

    function swapExact(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public pure returns (uint256) {
        // Zero-value
        require(uints[0] == 0,"Assert Zero-value");

        // Decode extradata
        (address[2] memory tokenGiveGet, uint256[2] memory amountGiveGet) = abi
            .decode(extra, (address[2], uint256[2]));

        // Call target = token to give
        require(addresses[2] == tokenGiveGet[0],"Call target = token to give");
        // Call type = call
        require(howToCalls[0] == AuthenticatedProxy.HowToCall.Call,"Call type = call");
        // Assert calldata
        require(
            ArrayUtils.arrayEq(
                data,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    addresses[1],
                    addresses[4],
                    amountGiveGet[0]
                )
            ),
            "Assert calldata"
        );

        require(addresses[5] == tokenGiveGet[1],"Assert tokenGiveGet");
        // Countercall type = call
        require(howToCalls[1] == AuthenticatedProxy.HowToCall.Call,"Assert Countercall type = call");
        // Assert countercalldata
        require(
            ArrayUtils.arrayEq(
                counterdata,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    addresses[4],
                    addresses[1],
                    amountGiveGet[1]
                )
            ),
            "Assert countercalldata"
        );

        // Mark filled.
        return 1;
    }

    function swapForever(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public pure returns (uint256) {
        // Calculate function signature
        bytes memory sig = ArrayUtils.arrayTake(
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            4
        );

        // Zero-value
        require(uints[0] == 0,"swapForever Zero-value");

        // Decode extradata
        (
            address[2] memory tokenGiveGet,
            uint256[2] memory numeratorDenominator
        ) = abi.decode(extra, (address[2], uint256[2]));

        // Call target = token to give
        require(addresses[2] == tokenGiveGet[0]);
        // Call type = call
        require(howToCalls[0] == AuthenticatedProxy.HowToCall.Call);
        // Check signature
        require(ArrayUtils.arrayEq(sig, ArrayUtils.arrayTake(data, 4)));
        // Decode calldata
        (address callFrom, address callTo, uint256 amountGive) = abi.decode(
            ArrayUtils.arrayDrop(data, 4),
            (address, address, uint256)
        );
        // Assert from
        require(callFrom == addresses[1]);
        // Assert to
        require(callTo == addresses[4]);

        // Countercall target = token to get
        require(addresses[5] == tokenGiveGet[1]);
        // Countercall type = call
        require(howToCalls[1] == AuthenticatedProxy.HowToCall.Call);
        // Check signature
        require(ArrayUtils.arrayEq(sig, ArrayUtils.arrayTake(counterdata, 4)));
        // Decode countercalldata
        (
            address countercallFrom,
            address countercallTo,
            uint256 amountGet
        ) = abi.decode(
                ArrayUtils.arrayDrop(counterdata, 4),
                (address, address, uint256)
            );
        // Assert from
        require(countercallFrom == addresses[4]);
        // Assert to
        require(countercallTo == addresses[1]);

        // Assert ratio
        // ratio = min get/give
        require(
            SafeMath.mul(amountGet, numeratorDenominator[1]) >=
                SafeMath.mul(amountGive, numeratorDenominator[0])
        );

        // Order will be set with maximumFill = 2 (to allow signature caching)
        return 1;
    }
}
