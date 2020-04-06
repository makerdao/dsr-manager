// DsrManager.sol
// Copyright (C) 2020 Maker Ecosystem Growth Holdings, INC.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.5.12;

contract VatLike {
    function hope(address) external;
    function move(address, address, uint256) external;
}

contract PotLike {
    function vat() external view returns (address);
    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;
}

contract JoinLike {
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

contract GemLike {
    function balanceOf(address) public returns (uint);
    function transferFrom(address,address,uint256) external returns (bool);
    function approve(address,uint256) external returns (bool);
}

contract DustTrackingDsrManager {
    PotLike  public pot;
    GemLike  public dai;
    JoinLike public daiJoin;

    struct Balance {
        uint256 pie;
        uint256 dust;
    }
    mapping (address => Balance) bals;

    event Join(address indexed dst, uint256 wad);
    event Exit(address indexed dst, uint256 wad);

    uint256 constant RAY = 10 ** 27;
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    constructor(address pot_, address daiJoin_) public {
        pot = PotLike(pot_);
        daiJoin = JoinLike(daiJoin_);
        dai = GemLike(daiJoin.dai());

        VatLike vat = VatLike(pot.vat());
        vat.hope(address(daiJoin));
        vat.hope(address(pot));
        dai.approve(address(daiJoin), uint256(-1));
    }

    // Maximum balance that can be withdrawn as ERC20 DAI by a particular address.
    function daiBalance(address usr) external returns (uint256 wad) {
        uint256 chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        wad = add(mul(chi, bals[usr].pie), bals[usr].dust) / RAY;
    }

    // wad is denominated in dai
    function join(address src, uint256 wad) public {
        // join DAI into the Vat under this contract's address
        // src must approve this contract
        dai.transferFrom(src, address(this), wad);
        daiJoin.join(address(this), wad);

        // Read values (update chi if necessary)
        Balance storage bal = bals[msg.sender];
        uint256 chi = (now > pot.rho()) ? pot.drip() : pot.chi();

        // join as much dai as possible into the Pot
        uint256 pie = add(mul(wad, RAY), bal.dust) / chi;
        pot.join(pie);

        // update balance of sender
        // based on equality: (pie'*chi + dust') - (pie*chi + dust) = wad*RAY
        // where values with a "'" are post-update
        uint256 newPie = add(bal.pie, pie);
        bal.dust = sub(add(add(mul(wad, RAY), mul(bal.pie, chi)), bal.dust), newPie);
        bal.pie = newPie;

        emit Join(src, wad);
    }

    // ergonomic method to eliminate any race condition on DAI balance of src
    function joinAll(address src) external {
        join(src, dai.balanceOf(src));
    }

    // wad is denominated in dai
    function exit(address dst, uint256 wad) external {
        // Read values (update chi if necessary)
        Balance storage bal = bals[msg.sender];
        uint256 chi = (now > pot.rho()) ? pot.drip() : pot.chi();

        // calculate amount to withdraw from Pot
        // pie derived via: dust + pie*chi >= wad*RAY
        uint256 pie = add(sub(mul(wad, RAY), bal.dust), sub(chi, 1)) / chi;
        require(bal.pie >= pie, "insufficient-balance");
        pot.exit(pie);

        // update values and calculate withdrawal amount
        bal.pie = sub(bal.pie, pie);
        uint256 amt = add(mul(chi, pie), bal.dust);
        bal.dust = amt % RAY;
        amt /= RAY;

        // send amt ERC20 DAI to dst
        daiJoin.exit(dst, amt);

        emit Exit(dst, amt);
    }

    // remove as much ERC20 DAI as possible; leaves dust
    function exitAll(address dst) public {
        // Read values (update chi if necessary)
        Balance storage balance = bals[msg.sender];
        uint256 chi = (now > pot.rho()) ? pot.drip() : pot.chi();

        // exit sender's entire pie
        uint256 pie = balance.pie;
        pot.exit(pie);

        // update values and calculate withdrawal amount
        balance.pie = 0;
        uint256 amt = add(mul(chi, pie), balance.dust);
        balance.dust = amt % RAY;
        amt /= RAY;

        // send amt ERC20 DAI to dst
        daiJoin.exit(dst, amt);

        emit Exit(dst, amt);
    }

    // rad is internal dai, i.e. a 45 decimal digit fixed-point integer
    function exitDust(address dst, uint256 rad) public {
        VatLike(pot.vat()).move(msg.sender, dst, rad);
        bals[msg.sender].dust = sub(bals[msg.sender].dust, rad);
        // TODO: event?
    }

    // Withdraws as much ERC20 DAI to dst as possible,
    // and transfers the dust to dst in the Vat.
    function exitEverything(address dst) external {
        exitAll(dst);
        exitDust(dst, bals[msg.sender].dust);
    }
}
