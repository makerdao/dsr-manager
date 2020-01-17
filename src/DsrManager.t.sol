pragma solidity ^0.5.15;

import "ds-test/test.sol";

import "./DsrManager.sol";

contract DsrManagerTest is DSTest {
    DsrManager manager;

    function setUp() public {
        manager = new DsrManager();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
