// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PropaneMaintainerService} from "../src/maintainer/PropaneMaintainerService.sol";
import {PropaneInstitutional} from "../src/institution/propaneInstitutional.sol";
import {PropaneComplianceRegistry} from "../src/registry/propaneComplianceRegistry.sol";
import {PropaneComplianceEngine} from "../src/compliance/orbex/propaneEngine.sol";
import {PropaneCensus} from "../src/compliance/census/propaneCensus.sol";
import {PropaneInvestorLockHead} from "../src/compliance/dependency/heads/propaneInvestorLockHead.sol";
import {PropaneSecurityToken} from "../src/security/propaneSecurityToken.sol";
import {PropaneRoles, PropaneServices} from "../src/common/PropaneConstants.sol";

/// @notice Deploys the Propane system behind UUPS proxies on an fhEVM-enabled chain (the FHE
///         coprocessor configuration is selected by chain id in ZamaConfig: mainnet, Sepolia, local).
/// @dev Not run as part of this build. Broadcasting requires explicit approval. Environment:
///      ISSUER, OPERATOR, TRANSFER_AGENT, RECORD_KEEPER, TOKEN_NAME, TOKEN_SYMBOL. The broadcasting
///      key becomes super owner; transfer it to a multisig or timelock immediately after deployment.
///      The rulebook starts with every optional rule disabled and flowback blocked indefinitely
///      (prior-art semantics of an unset end time); schedule the offering's rulebook with
///      scheduleConfig, which takes effect after CONFIG_DELAY.
contract DeployPropane is Script {
    function run() external {
        address issuer = vm.envAddress("ISSUER");
        address operator = vm.envAddress("OPERATOR");
        address transferAgent = vm.envAddress("TRANSFER_AGENT");
        address recordKeeper = vm.envAddress("RECORD_KEEPER");
        string memory name = vm.envString("TOKEN_NAME");
        string memory symbol = vm.envString("TOKEN_SYMBOL");

        vm.startBroadcast();
        PropaneMaintainerService maintainer = PropaneMaintainerService(
            address(new ERC1967Proxy(address(new PropaneMaintainerService()), abi.encodeWithSignature("initialize()")))
        );
        PropaneInstitutional loc = PropaneInstitutional(
            address(
                new ERC1967Proxy(
                    address(new PropaneInstitutional()),
                    abi.encodeCall(PropaneInstitutional.initialize, (address(maintainer)))
                )
            )
        );
        maintainer.addUniversalRole(issuer, PropaneRoles.ROLE_OWNER);
        maintainer.addUniversalRole(operator, PropaneRoles.ROLE_PROPANE);
        maintainer.addUniversalRole(transferAgent, PropaneRoles.ROLE_OFFICER);

        bytes memory initLoc = abi.encodeWithSignature("initialize(address)", address(loc));
        address registry = address(new ERC1967Proxy(address(new PropaneComplianceRegistry()), initLoc));
        PropaneComplianceEngine.Config memory cfg;
        address engine = address(
            new ERC1967Proxy(
                address(new PropaneComplianceEngine()),
                abi.encodeCall(PropaneComplianceEngine.initialize, (address(loc), cfg))
            )
        );
        address census = address(new ERC1967Proxy(address(new PropaneCensus()), initLoc));
        address lockHead = address(new ERC1967Proxy(address(new PropaneInvestorLockHead()), initLoc));
        address token = address(
            new ERC1967Proxy(
                address(new PropaneSecurityToken()),
                abi.encodeCall(PropaneSecurityToken.initialize, (address(loc), name, symbol, 0))
            )
        );

        loc.setInstitutionalService(PropaneServices.SVC_REGISTRY, registry);
        loc.setInstitutionalService(PropaneServices.SVC_COMPLIANCE, engine);
        loc.setInstitutionalService(PropaneServices.SVC_CENSUS, census);
        loc.setInstitutionalService(PropaneServices.SVC_LOCK_HEAD, lockHead);
        loc.setInstitutionalService(PropaneServices.SVC_TOKEN, token);
        loc.setInstitutionalService(PropaneServices.SVC_RECORD_KEEPER, recordKeeper);
        vm.stopBroadcast();

        console2.log("maintainer", address(maintainer));
        console2.log("locator", address(loc));
        console2.log("registry", registry);
        console2.log("engine", engine);
        console2.log("census", census);
        console2.log("lockHead", lockHead);
        console2.log("token", token);
    }
}
