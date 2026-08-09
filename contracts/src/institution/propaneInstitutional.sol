//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;
import {IPropaneInstitutional} from "./IPropaneInstitutional.sol";
import {IPropaneSecurityToken} from "../security/IPropaneSecurityToken.sol";
import {PropaneInstitutionalStore} from "../silo/storage/propaneInstitutionalStore.sol";
import {IPropaneInvestorEOAHead} from "../compliance/dependency/heads/IPropaneInvestorEOAHead.sol";
import {IPropaneInvestorTempBarredHead} from "../compliance/dependency/heads/IPropaneInvestorTempBarredHead.sol";
import {IPropaneInvestorWhitelistHead} from "../compliance/dependency/heads/IPropaneInvestorWhitelistHead.sol";
import {IPropaneInvestorBlacklistHead} from "../compliance/dependency/heads/IPropaneInvestorBlacklistHead.sol";

abstract contract PropaneInstitutional is IPropaneInstitutional, PropaneInstitutionalStore {
    ///@notice this is service side contract or institutional side (mostly getter) contract
    ///for handling institutional logic
    /**
     * services made available for user
     * 1/getInstitutionalService
     * 2/getEOAHead
     * 3/getBarringHead
     * 4/getWhitelistingHead
     * 5/getComplianceHead
     * 6/getBlacklistHead
     * 7/getMaintainer
     */
    function getInstitutionalService(uint256 serviceId) public view override returns (address) {
        return services[serviceId];
    }

    function getEOAHead(uint256 eoaId) public view returns (IPropaneInvestorEOAHead) {
        return IPropaneInvestorEOAHead(getInstitutionalService(EOA_HEAD));
    }

    function getBarringHead(uint256 barringId) public view returns (IPropaneInvestorTempBarredHead) {
        return IPropaneInvestorTempBarredHead(getInstitutionalService(BARRING_HEAD));
    }

    function getWhitelistingHead(uint256 whitelistingId) public view returns (IPropaneInvestorWhitelistHead) {
        return IPropaneInvestorWhitelistHead(getInstitutionalService(WHITELISTING_HEAD));
    }

    function getBlacklistingHead(uint256 blacklistingId) public view returns (IPropaneInvestorBlacklistHead) {
        return IPropaneInvestorBlacklistHead(getInstitutionalService(BLACKLISTING_HEAD));
    }
}
