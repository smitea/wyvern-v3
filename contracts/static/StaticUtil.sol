/*

    StaticUtil - static call utility contract

*/

pragma solidity 0.7.5;

import "../lib/StaticCaller.sol";
import "../lib/ArrayUtils.sol";
import "../registry/AuthenticatedProxy.sol";

contract StaticUtil is StaticCaller {
    address public atomicizer;

    function any(
        bytes memory,
        address[7] memory,
        AuthenticatedProxy.HowToCall[2] memory,
        uint256[6] memory,
        bytes memory,
        bytes memory
    ) public pure returns (uint256) {
        /*
           Accept any call.
           Useful e.g. for matching-by-transaction, where you authorize the counter-call by sending the transaction and don't need to re-check it.
           Return fill "1".
        */

        return 1;
    }

    function anySingle(
        bytes memory,
        address[7] memory,
        AuthenticatedProxy.HowToCall,
        uint256[6] memory,
        bytes memory
    ) public pure {
        /* No checks. */
    }

    function anyNoFill(
        bytes memory,
        address[7] memory,
        AuthenticatedProxy.HowToCall[2] memory,
        uint256[6] memory,
        bytes memory,
        bytes memory
    ) public pure returns (uint256) {
        /*
           Accept any call.
           Useful e.g. for matching-by-transaction, where you authorize the counter-call by sending the transaction and don't need to re-check it.
           Return fill "0".
        */

        return 0;
    }

    function anyAddOne(
        bytes memory,
        address[7] memory,
        AuthenticatedProxy.HowToCall[2] memory,
        uint256[6] memory uints,
        bytes memory,
        bytes memory
    ) public pure returns (uint256) {
        /*
           Accept any call.
           Useful e.g. for matching-by-transaction, where you authorize the counter-call by sending the transaction and don't need to re-check it.
           Return the current fill plus 1.
        */

        return uints[5] + 1;
    }

    function split(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public view returns (uint256) {
        (
            address[2] memory targets,
            bytes4[2] memory selectors,
            bytes memory firstExtradata,
            bytes memory secondExtradata
        ) = abi.decode(extra, (address[2], bytes4[2], bytes, bytes));

        /* Split into two static calls: one for the call, one for the counter-call, both with metadata. */

        /* Static call to check the call. */
        require(
            staticCall(
                targets[0],
                abi.encodeWithSelector(
                    selectors[0],
                    firstExtradata,
                    addresses,
                    howToCalls[0],
                    uints,
                    data
                )
            )
        );

        /* Static call to check the counter-call. */
        require(
            staticCall(
                targets[1],
                abi.encodeWithSelector(
                    selectors[1],
                    secondExtradata,
                    [
                        addresses[3],
                        addresses[4],
                        addresses[5],
                        addresses[0],
                        addresses[1],
                        addresses[2],
                        addresses[6]
                    ],
                    howToCalls[1],
                    uints,
                    counterdata
                )
            )
        );

        return 1;
    }

    function splitAddOne(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public view returns (uint256) {
        split(extra, addresses, howToCalls, uints, data, counterdata);
        return uints[5] + 1;
    }

    function and(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public view {
        (
            address[] memory addrs,
            bytes4[] memory selectors,
            uint256[] memory extradataLengths,
            bytes memory extradatas
        ) = abi.decode(extra, (address[], bytes4[], uint256[], bytes));

        require(addrs.length == extradataLengths.length);

        uint256 j = 0;
        for (uint256 i = 0; i < addrs.length; i++) {
            bytes memory extradata = new bytes(extradataLengths[i]);
            for (uint256 k = 0; k < extradataLengths[i]; k++) {
                extradata[k] = extradatas[j];
                j++;
            }
            require(
                staticCall(
                    addrs[i],
                    abi.encodeWithSelector(
                        selectors[i],
                        extradata,
                        addresses,
                        howToCalls,
                        uints,
                        data,
                        counterdata
                    )
                )
            );
        }
    }

    function or(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory data,
        bytes memory counterdata
    ) public view {
        (
            address[] memory addrs,
            bytes4[] memory selectors,
            uint256[] memory extradataLengths,
            bytes memory extradatas
        ) = abi.decode(extra, (address[], bytes4[], uint256[], bytes));

        require(
            addrs.length == extradataLengths.length,
            "Different number of static call addresses and extradatas"
        );

        uint256 j = 0;
        for (uint256 i = 0; i < addrs.length; i++) {
            bytes memory extradata = new bytes(extradataLengths[i]);
            for (uint256 k = 0; k < extradataLengths[i]; k++) {
                extradata[k] = extradatas[j];
                j++;
            }
            if (
                staticCall(
                    addrs[i],
                    abi.encodeWithSelector(
                        selectors[i],
                        extradata,
                        addresses,
                        howToCalls,
                        uints,
                        data,
                        counterdata
                    )
                )
            ) {
                return;
            }
        }

        revert("No static calls succeeded");
    }

    function sequenceExact(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall howToCall,
        uint256[6] memory uints,
        bytes memory cdata
    ) public view {
        (
            address[] memory addrs,
            uint256[] memory extradataLengths,
            bytes4[] memory selectors,
            bytes memory extradatas
        ) = abi.decode(extra, (address[], uint256[], bytes4[], bytes));

        /* Assert DELEGATECALL to atomicizer library with given call sequence, split up predicates accordingly.
           e.g. transferring two CryptoKitties in sequence. */

        require(addrs.length == extradataLengths.length);

        (
            address[] memory caddrs,
            uint256[] memory cvals,
            uint256[] memory clengths,
            bytes memory calldatas
        ) = abi.decode(
                ArrayUtils.arrayDrop(cdata, 4),
                (address[], uint256[], uint256[], bytes)
            );

        require(addresses[2] == atomicizer);
        require(howToCall == AuthenticatedProxy.HowToCall.DelegateCall);
        require(addrs.length == caddrs.length); // Exact calls only

        for (uint256 i = 0; i < addrs.length; i++) {
            require(cvals[i] == 0);
        }

        sequence(
            caddrs,
            clengths,
            calldatas,
            addresses,
            uints,
            addrs,
            extradataLengths,
            selectors,
            extradatas
        );
    }

    function dumbSequenceExact(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall[2] memory howToCalls,
        uint256[6] memory uints,
        bytes memory cdata,
        bytes memory
    ) public view returns (uint256) {
        sequenceExact(extra, addresses, howToCalls[0], uints, cdata);

        return 1;
    }

    function sequenceAnyAfter(
        bytes memory extra,
        address[7] memory addresses,
        AuthenticatedProxy.HowToCall howToCall,
        uint256[6] memory uints,
        bytes memory cdata
    ) public view {
        (
            address[] memory addrs,
            uint256[] memory extradataLengths,
            bytes4[] memory selectors,
            bytes memory extradatas
        ) = abi.decode(extra, (address[], uint256[], bytes4[], bytes));

        /* Assert DELEGATECALL to atomicizer library with given call sequence, split up predicates accordingly.
           e.g. transferring two CryptoKitties in sequence. */

        require(addrs.length == extradataLengths.length);

        (
            address[] memory caddrs,
            uint256[] memory cvals,
            uint256[] memory clengths,
            bytes memory calldatas
        ) = abi.decode(
                ArrayUtils.arrayDrop(cdata, 4),
                (address[], uint256[], uint256[], bytes)
            );

        require(addresses[2] == atomicizer);
        require(howToCall == AuthenticatedProxy.HowToCall.DelegateCall);
        require(addrs.length <= caddrs.length); // Extra calls OK

        for (uint256 i = 0; i < addrs.length; i++) {
            require(cvals[i] == 0);
        }

        sequence(
            caddrs,
            clengths,
            calldatas,
            addresses,
            uints,
            addrs,
            extradataLengths,
            selectors,
            extradatas
        );
    }

    function sequence(
        address[] memory caddrs,
        uint256[] memory clengths,
        bytes memory calldatas,
        address[7] memory addresses,
        uint256[6] memory uints,
        address[] memory addrs,
        uint256[] memory extradataLengths,
        bytes4[] memory selectors,
        bytes memory extradatas
    ) internal view {
        uint256 j = 0;
        uint256 l = 0;
        for (uint256 i = 0; i < addrs.length; i++) {
            bytes memory extradata = new bytes(extradataLengths[i]);
            for (uint256 k = 0; k < extradataLengths[i]; k++) {
                extradata[k] = extradatas[j];
                j++;
            }
            bytes memory data = new bytes(clengths[i]);
            for (uint256 m = 0; m < clengths[i]; m++) {
                data[m] = calldatas[l];
                l++;
            }
            addresses[2] = caddrs[i];
            require(
                staticCall(
                    addrs[i],
                    abi.encodeWithSelector(
                        selectors[i],
                        extradata,
                        addresses,
                        AuthenticatedProxy.HowToCall.Call,
                        uints,
                        data
                    )
                )
            );
        }
        require(j == extradatas.length);
    }
}
