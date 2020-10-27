pragma solidity ^0.6.0;


interface IEncoreVault {
    function addPendingRewards(uint _amount) external;
    function stakedLPTokens(uint256 _pid, address _user) external view returns (uint256);
}
