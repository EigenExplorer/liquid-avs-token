// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPriceConstants} from "../../interfaces/IPriceConstants.sol";

/**
 * @title PriceConstants
 * @notice Concrete implementation of IPriceConstants
 */
contract PriceConstants is IPriceConstants {
    // Token addresses
    function ETH() external pure override returns (address) {
        return 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }
    function ETHx() external pure override returns (address) {
        return 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
    }

    function OSETH() external pure override returns (address) {
        return 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
    }
    function SFRxETH() external pure override returns (address) {
        return 0xac3E018457B222d93114458476f3E3416Abbe38F;
    }
    function RETH() external pure override returns (address) {
        return 0xae78736Cd615f374D3085123A210448E74Fc6393;
    }
    function STETH() external pure override returns (address) {
        return 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    }
    function CBETH() external pure override returns (address) {
        return 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    }
    function OETH() external pure override returns (address) {
        return 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    }
    function METH() external pure override returns (address) {
        return 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    }
    function LSETH() external pure override returns (address) {
        return 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
    }
    function SWETH() external pure override returns (address) {
        return 0xf951E335afb289353dc249e82926178EaC7DEd78;
    }
    function ANKR_ETH() external pure override returns (address) {
        return 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    }
    function WSTETH() external pure override returns (address) {
        return 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    }
    function UNIBTC() external pure override returns (address) {
        return 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;
    }
    function STBTC() external pure override returns (address) {
        return 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;
    }
    function WBETH() external pure override returns (address) {
        return 0xa2E3356610840701BDf5611a53974510Ae27E2e1;
    }

    // Source types
    function SOURCE_TYPE_CHAINLINK() external pure override returns (uint8) {
        return 1;
    }
    function SOURCE_TYPE_CURVE() external pure override returns (uint8) {
        return 2;
    }
    function SOURCE_TYPE_BTC_CHAINED() external pure override returns (uint8) {
        return 3;
    }
    function SOURCE_TYPE_PROTOCOL() external pure override returns (uint8) {
        return 4;
    }

    // Chainlink feed addresses
    function CHAINLINK_RETH_ETH() external pure override returns (address) {
        return 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    }
    function CHAINLINK_STETH_ETH() external pure override returns (address) {
        return 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    }
    function CHAINLINK_CBETH_ETH() external pure override returns (address) {
        return 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    }
    function CHAINLINK_METH_ETH() external pure override returns (address) {
        return 0x5b563107C8666d2142C216114228443B94152362;
    }
    function CHAINLINK_OETH_ETH() external pure override returns (address) {
        return 0x703118C4CbccCBF2AB31913e0f8075fbbb15f563;
    }
    function CHAINLINK_BTC_ETH() external pure override returns (address) {
        return 0xdeb288F737066589598e9214E782fa5A8eD689e8;
    }
    function CHAINLINK_UNIBTC_BTC() external pure override returns (address) {
        return 0x861d15F8a4059cb918bD6F3670adAEB1220B298f;
    }
    function CHAINLINK_STBTC_BTC() external pure override returns (address) {
        return 0xD93571A6201978976e37c4A0F7bE17806f2Feab2;
    }

    // Curve pool addresses
    function LSETH_CURVE_POOL() external pure override returns (address) {
        return 0x6c60d69348f3430bE4B7cf0155a4FD8f6CA9353B;
    }
    function ETHx_CURVE_POOL() external pure override returns (address) {
        return 0x64939a882C7d1b096241678b7a3A57eD19445485;
    }
    function ANKR_ETH_CURVE_POOL() external pure override returns (address) {
        return 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2;
    }
    function OSETH_CURVE_POOL() external pure override returns (address) {
        return 0xC2A6798447BB70E5abCf1b0D6aeeC90BC14FCA55;
    }
    function SWETH_CURVE_POOL() external pure override returns (address) {
        return 0x8d30BE1e51882688ee8F976DeB9bdd411b74BEf3;
    }

    // Protocol contract addresses
    function RETH_CONTRACT() external pure override returns (address) {
        return 0xae78736Cd615f374D3085123A210448E74Fc6393;
    }
    function STETH_CONTRACT() external pure override returns (address) {
        return 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    }
    function CBETH_CONTRACT() external pure override returns (address) {
        return 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    }
    function ETHx_CONTRACT() external pure override returns (address) {
        return 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
    }
    function OSETH_CONTRACT() external pure override returns (address) {
        return 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
    }
    function SFRxETH_CONTRACT() external pure override returns (address) {
        return 0xac3E018457B222d93114458476f3E3416Abbe38F;
    }
    function SWETH_CONTRACT() external pure override returns (address) {
        return 0xf951E335afb289353dc249e82926178EaC7DEd78;
    }
    function WSTETH_CONTRACT() external pure override returns (address) {
        return 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    }
    function ANKR_ETH_CONTRACT() external pure override returns (address) {
        return 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    }
    function LSETH_CONTRACT() external pure override returns (address) {
        return 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
    }
    function OETH_CONTRACT() external pure override returns (address) {
        return 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;
    }
    function METH_CONTRACT() external pure override returns (address) {
        return 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    }
    function UNIBTC_CONTRACT() external pure override returns (address) {
        return 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;
    }
    function WBETH_CONTRACT() external pure override returns (address) {
        return 0xa2E3356610840701BDf5611a53974510Ae27E2e1; // Using proxy address as primary
    }
    function STBTC_ACCOUNTANT_CONTRACT()
        external
        pure
        override
        returns (address)
    {
        return 0xEa23aC6D7D11f6b181d6B98174D334478ADAe6b0;
    }

    // Function selectors
    function SELECTOR_GET_EXCHANGE_RATE()
        external
        pure
        override
        returns (bytes4)
    {
        return 0x8af07e89;
    } // getExchangeRate()
    function SELECTOR_GET_POOLED_ETH_BY_SHARES()
        external
        pure
        override
        returns (bytes4)
    {
        return 0x7a28fb88;
    } // getPooledEthByShares(uint256)
    function SELECTOR_EXCHANGE_RATE() external pure override returns (bytes4) {
        return 0x3ba0b9a9;
    } // exchangeRate()
    function SELECTOR_CONVERT_TO_ASSETS()
        external
        pure
        override
        returns (bytes4)
    {
        return 0x07a2d13a;
    } // convertToAssets(uint256)
    function SELECTOR_SWETH_TO_ETH_RATE()
        external
        pure
        override
        returns (bytes4)
    {
        return 0x8d928af8;
    } // swETHToETHRate()
    function SELECTOR_STETH_PER_TOKEN()
        external
        pure
        override
        returns (bytes4)
    {
        return 0x035faf82;
    } // stEthPerToken()
    function SELECTOR_RATIO() external pure override returns (bytes4) {
        return 0xce1e09c0;
    } // ratio()
    function SELECTOR_UNDERLYING_BALANCE_FROM_SHARES()
        external
        pure
        override
        returns (bytes4)
    {
        return 0x0a8a5f53;
    } // underlyingBalanceFromShares(uint256)
    function SELECTOR_METH_TO_ETH() external pure override returns (bytes4) {
        return 0xc9f04442;
    } // mETHToETH(uint256)
    function SELECTOR_GET_RATE() external pure override returns (bytes4) {
        return 0x679aefce;
    } // getRate()

    // Standard argument
    function DEFAULT_AMOUNT() external pure override returns (uint256) {
        return 1e18;
    }
}