/*

  << Static Market contract >>

*/

pragma solidity 0.7.5;

import "./lib/ArrayUtils.sol";
import "./registry/AuthenticatedProxy.sol";

/**
 * @title StaticMarket
 * @author Wyvern Protocol Developers
 */
contract StaticMarket {
    string public constant name = "Static Market";

    constructor() public {}

    function anyERC1155ForERC20(
        // staticExtradata
        bytes memory extra,
        // order.registry,
        // order.maker,
        // call.target,
        // counterorder.registry,
        // counterorder.maker,
        // countercall.target,
        // matcher
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        // value,
        // order.maximumFill,
        // order.listingTime,
        // order.expirationTime,
        // counterorder.listingTime,
        // fill
        uint256[6] memory uints,
        // firstCall
        bytes memory data,
        // secondCall
        bytes memory counterdata
    ) public pure returns (uint256) {
        require(uints[0] == 0, "anyERC1155ForERC20: Zero value required");
        require(
            howToCalls[0] == AuthenticatedProxy.HowToCall.Call,
            "anyERC1155ForERC20: call must be a direct call"
        );

        (
            // ERC1155 合约地址
            // ERC20 合约地址
            address[2] memory tokenGiveGet,
            // 5 (TokenID), 1(买的份数), 10000(单价)
            uint256[3] memory tokenIdAndNumeratorDenominator
        ) = abi.decode(extra, (address[2], uint256[3]));

        require(
            tokenIdAndNumeratorDenominator[1] > 0,
            "anyERC20ForERC1155: numerator must be larger than zero"
        );
        require(
            tokenIdAndNumeratorDenominator[2] > 0,
            "anyERC20ForERC1155: denominator must be larger than zero"
        );
        // ERC 1155 合约地址
        require(
            addresses[2] == tokenGiveGet[0],
            "anyERC1155ForERC20: call target must equal address of token to give"
        );
        // ERC 20 合约地址
        require(
            addresses[5] == tokenGiveGet[1],
            "anyERC1155ForERC20: countercall target must equal address of token to get"
        );

        // 买的份数, 买的的单价
        uint256[2] memory call_amounts = [
            getERC1155AmountFromCalldata(data),
            getERC20AmountFromCalldata(counterdata)
        ];

        // Fill = fill + 买的份数
        uint256 new_fill = SafeMath.add(uints[5], call_amounts[0]);
        require(
            new_fill <= uints[1],
            "anyERC1155ForERC20: new fill exceeds maximum fill"
        );
        // 买的份数 * (买的的单价 == 单价 * 买的份数) > 0
        require(
            SafeMath.mul(tokenIdAndNumeratorDenominator[1], call_amounts[1]) ==
                SafeMath.mul(
                    tokenIdAndNumeratorDenominator[2],
                    call_amounts[0]
                ),
            "anyERC1155ForERC20: wrong ratio"
        );
        checkERC1155Side(
            data,
            addresses[1],
            addresses[4],
            tokenIdAndNumeratorDenominator[0],
            call_amounts[0]
        );
        // checkAtomcizeSide(
        //     counterdata,
        //     addresses[4],
        //     addresses[1],
        //     call_amounts[1]
        // );

        return new_fill;
    }

    function anyERC20ForERC1155(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public pure returns (uint256) {
        require(uints[0] == 0, "anyERC20ForERC1155: Zero value required");
        require(
            howToCalls[0] == AuthenticatedProxy.HowToCall.DelegateCall,
            "anyERC20ForERC1155: call must be a delegate call"
        );

        (
            address[2] memory tokenGiveGet,
            uint256[3] memory tokenIdAndNumeratorDenominator
        ) = abi.decode(extra, (address[2], uint256[3]));

        require(
            tokenIdAndNumeratorDenominator[1] > 0,
            "anyERC20ForERC1155: numerator must be larger than zero"
        );
        require(
            tokenIdAndNumeratorDenominator[2] > 0,
            "anyERC20ForERC1155: denominator must be larger than zero"
        );
        require(
            addresses[2] == tokenGiveGet[0],
            "anyERC20ForERC1155: call target must equal address of token to get"
        );
        require(
            addresses[5] == tokenGiveGet[1],
            "anyERC20ForERC1155: countercall target must equal address of token to give"
        );

        uint256[2] memory call_amounts = [
            getERC1155AmountFromCalldata(counterdata),
            getERC20AmountFromCalldata(data)
        ];
        uint256 new_fill = SafeMath.add(uints[5], call_amounts[1]);
        require(
            new_fill <= uints[1],
            "anyERC20ForERC1155: new fill exceeds maximum fill"
        );
        require(
            SafeMath.mul(tokenIdAndNumeratorDenominator[1], call_amounts[0]) ==
                SafeMath.mul(
                    tokenIdAndNumeratorDenominator[2],
                    call_amounts[1]
                ),
            "anyERC20ForERC1155: wrong ratio"
        );
        checkERC1155Side(
            counterdata,
            addresses[4],
            addresses[1],
            tokenIdAndNumeratorDenominator[0],
            call_amounts[0]
        );
        // checkAtomcizeSide(data, addresses[1], addresses[4], call_amounts[1]);

        return new_fill;
    }

    function anyERC20ForERC20(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public pure returns (uint256) {
        require(uints[0] == 0, "anyERC20ForERC20: Zero value required");
        require(
            howToCalls[0] == AuthenticatedProxy.HowToCall.Call,
            "anyERC20ForERC20: call must be a direct call"
        );

        (
            address[2] memory tokenGiveGet,
            uint256[2] memory numeratorDenominator
        ) = abi.decode(extra, (address[2], uint256[2]));

        require(
            numeratorDenominator[0] > 0,
            "anyERC20ForERC20: numerator must be larger than zero"
        );
        require(
            numeratorDenominator[1] > 0,
            "anyERC20ForERC20: denominator must be larger than zero"
        );
        require(
            addresses[2] == tokenGiveGet[0],
            "anyERC20ForERC20: call target must equal address of token to give"
        );
        require(
            addresses[5] == tokenGiveGet[1],
            "anyERC20ForERC20: countercall target must equal address of token to get"
        );

        uint256[2] memory call_amounts = [
            getERC20AmountFromCalldata(data),
            getERC20AmountFromCalldata(counterdata)
        ];
        uint256 new_fill = SafeMath.add(uints[5], call_amounts[0]);
        require(
            new_fill <= uints[1],
            "anyERC20ForERC20: new fill exceeds maximum fill"
        );
        require(
            SafeMath.mul(numeratorDenominator[0], call_amounts[0]) ==
                SafeMath.mul(numeratorDenominator[1], call_amounts[1]),
            "anyERC20ForERC20: wrong ratio"
        );
        checkERC20Side(data, addresses[1], addresses[4], call_amounts[0]);
        checkERC20Side(
            counterdata,
            addresses[4],
            addresses[1],
            call_amounts[1]
        );

        return new_fill;
    }

    function ERC721ForERC20(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public pure returns (uint256) {
        require(uints[0] == 0, "ERC721ForERC20: Zero value required");
        require(
            howToCalls[0] == AuthenticatedProxy.HowToCall.Call,
            "ERC721ForERC20: call must be a direct call"
        );

        (
            address[2] memory tokenGiveGet,
            uint256[2] memory tokenIdAndPrice
        ) = abi.decode(extra, (address[2], uint256[2]));

        require(
            tokenIdAndPrice[1] > 0,
            "ERC721ForERC20: ERC721 price must be larger than zero"
        );
        require(
            addresses[2] == tokenGiveGet[0],
            "ERC721ForERC20: call target must equal address of token to give"
        );
        require(
            addresses[5] == tokenGiveGet[1],
            "ERC721ForERC20: countercall target must equal address of token to get"
        );

        checkERC721Side(data, addresses[1], addresses[4], tokenIdAndPrice[0]);
        checkERC20Side(
            counterdata,
            addresses[4],
            addresses[1],
            tokenIdAndPrice[1]
        );

        return 1;
    }

    function ERC20ForERC721(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public pure returns (uint256) {
        require(uints[0] == 0, "ERC20ForERC721: Zero value required");
        require(
            howToCalls[0] == AuthenticatedProxy.HowToCall.Call,
            "ERC20ForERC721: call must be a direct call"
        );

        (
            address[2] memory tokenGiveGet,
            uint256[2] memory tokenIdAndPrice
        ) = abi.decode(extra, (address[2], uint256[2]));

        require(
            tokenIdAndPrice[1] > 0,
            "ERC20ForERC721: ERC721 price must be larger than zero"
        );
        require(
            addresses[2] == tokenGiveGet[0],
            "ERC20ForERC721: call target must equal address of token to give"
        );
        require(
            addresses[5] == tokenGiveGet[1],
            "ERC20ForERC721: countercall target must equal address of token to get"
        );

        checkERC721Side(
            counterdata,
            addresses[4],
            addresses[1],
            tokenIdAndPrice[0]
        );
        checkERC20Side(data, addresses[1], addresses[4], tokenIdAndPrice[1]);

        return 1;
    }

    function getERC1155AmountFromCalldata(bytes memory data)
        internal
        pure
        returns (uint256)
    {
        uint256 amount = abi.decode(
            ArrayUtils.arraySlice(data, 100, 32),
            (uint256)
        );
        return amount;
    }

    function getERC20AmountFromCalldata(bytes memory data)
        internal
        pure
        returns (uint256)
    {
        uint256 finalAmount = abi.decode(
            ArrayUtils.arraySlice(data, 616, 32),
            (uint256)
        );
        uint256 commissionAmount = abi.decode(
            ArrayUtils.arraySlice(data, 716, 32),
            (uint256)
        );
        uint256 royaltyAmount = abi.decode(
            ArrayUtils.arraySlice(data, 816, 32),
            (uint256)
        );
        return
            SafeMath.add(
                SafeMath.add(finalAmount, commissionAmount),
                royaltyAmount
            );
    }

    function checkERC1155Side(
        bytes memory data,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) internal pure {
        bytes memory assertData = abi.encodeWithSignature(
            "safeTransferFrom(address,address,uint256,uint256,bytes)",
            from,
            to,
            tokenId,
            amount,
            new bytes(0)
        );
        require(
            ArrayUtils.arrayEq(data, assertData),
            "ERC1155Side check Failed"
        );
    }

    function checkERC721Side(
        bytes memory data,
        address from,
        address to,
        uint256 tokenId
    ) internal pure {
        require(
            ArrayUtils.arrayEq(
                data,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    from,
                    to,
                    tokenId
                )
            ),
            "ERC721Side check Failed"
        );
    }

    function checkERC20Side(
        bytes memory data,
        address from,
        address to,
        uint256 amount
    ) internal pure {
        require(
            ArrayUtils.arrayEq(
                data,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    from,
                    to,
                    amount
                )
            ),
            "ERC20Side check Failed"
        );
    }

    function checkAtomcizeSide(
        bytes memory data,
        address from,
        address to,
        uint256 amount
    ) internal pure {
        require(
            ArrayUtils.arrayEq(
                data,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    from,
                    to,
                    amount
                )
            ),
            "AtomcizeSide check Failed"
        );
    }
}
