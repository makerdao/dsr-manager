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
}

contract PotLike {
    function chi() external returns (uint256);
    function rho() external returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;
}

contract JoinLike {
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

contract GemLike {
    function transferFrom(address,address,uint256) external returns (bool);
    function approve(address,uint256) external returns (bool);
}

contract DsrManager {
    VatLike  public vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
    PotLike  public pot = PotLike(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);
    JoinLike public daiJoin = JoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    GemLike  public daiToken = GemLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    uint256 public totalSupply;

    mapping (address => uint256) public pieOf;

    event Join(address indexed dst, uint256 wad);
    event Exit(address indexed dst, uint256 wad);

    uint constant RAY = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        // always rounds down
        z = mul(x, y) / RAY;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        // always rounds down
        z = mul(x, RAY) / y;
    }
    function rdivup(uint x, uint y) internal pure returns (uint z) {
        // always rounds up
        z = add(mul(x, RAY), sub(y, 1)) / y;
    }

    constructor() public {
        vat.hope(address(daiJoin));
        vat.hope(address(pot));

        daiToken.approve(address(daiJoin), uint(-1));
    }

    function dai(address usr) external returns (uint wad) {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        wad = rmul(chi, pieOf[usr]);
    }

    // wad is denominated in dai
    function join(address dst, uint wad) external {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        uint pie = rdiv(wad, chi);
        pieOf[dst] = add(pieOf[dst], pie);
        totalSupply    = add(totalSupply, pie);

        daiToken.transferFrom(msg.sender, address(this), wad);
        daiJoin.join(address(this), wad);
        pot.join(pie);
        emit Join(dst, wad);
    }

    // wad is denominated in dai
    function exit(address dst, uint wad) external {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        uint pie = rdivup(wad, chi);

        require(pieOf[msg.sender] >= pie, "insufficient-balance");

        pieOf[msg.sender] = sub(pieOf[msg.sender], pie);
        totalSupply = sub(totalSupply, pie);

        pot.exit(pie);
        uint256 amt = rmul(chi, pie);
        daiJoin.exit(msg.sender, amt);
        emit Exit(dst, amt);
    }

    function exitAll(address dst) external {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        uint pie = pieOf[msg.sender];

        pieOf[msg.sender] = 0;
        totalSupply = sub(totalSupply, pie);

        pot.exit(pie);
        uint256 amt = rmul(chi, pie);
        daiJoin.exit(msg.sender, amt);
        emit Exit(dst, amt);
    }
}
