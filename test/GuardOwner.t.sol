import "./utils/Config.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract ProtocolOwnerTest is Config {
    event ExecutionSuccess(bytes32 txHash, uint256 payment);


    function setUp() public {
        vm.startPrank(kakaroto);
        (safeProxy, delegationOwnerProxy, protocolOwnerProxy, guardOwnerProxy) = delegationWalletFactory.deploy(delegationController);

        safe = GnosisSafe(payable(safeProxy));
        protocolOwner = ProtocolOwner(protocolOwnerProxy);
        delegationOwner = DelegationOwner(delegationOwnerProxy);

        aclManager.addProtocolAdmin(kakaroto);
        allowedControllers.setDelegationControllerAllowance(karpincho, true);

        vm.stopPrank();
    }

    function test_initialize_exceptions() public {
        vm.startPrank(kakaroto);

        vm.expectRevert("Initializable: contract is already initialized");
        GuardOwner(guardOwnerProxy).initialize(address(0), address(0), address(0), address(0), address(0));

        address _guardOwnerBeacon = address(new UpgradeableBeacon(guardOwnerImpl));
        address _guardOwnerProxy = address(new BeaconProxy(_guardOwnerBeacon, new bytes(0)));

        vm.expectRevert(Errors.GuardOwner__initialize_invalidGuardBeacon.selector);
        GuardOwner(_guardOwnerProxy).initialize(address(0), address(0), address(0), address(0), address(0));

        address guard = address(GuardOwner(guardOwnerProxy).guard());

        vm.expectRevert(Errors.GuardOwner__initialize_invalidSafe.selector);
        GuardOwner(_guardOwnerProxy).initialize(guard, address(0), address(0), address(0), address(0));

        vm.expectRevert(Errors.GuardOwner__initialize_invalidOwner.selector);
        GuardOwner(_guardOwnerProxy).initialize(guard, address(safeProxy), address(0), address(0), address(0));

        vm.expectRevert(Errors.GuardOwner__initialize_invalidDelegationOwner.selector);
        GuardOwner(_guardOwnerProxy).initialize(guard, address(safeProxy), address(this), address(0), address(0));

        vm.expectRevert(Errors.GuardOwner__initialize_invalidProtocolOwner.selector);
        GuardOwner(_guardOwnerProxy).initialize(guard, address(safeProxy), address(this), address(this), address(0));

        vm.stopPrank();
    }
}
