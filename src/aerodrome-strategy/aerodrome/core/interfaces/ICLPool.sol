// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.18;

import {ICLPoolConstants} from "./pool/ICLPoolConstants.sol";
import {ICLPoolState} from "./pool/ICLPoolState.sol";
import {ICLPoolDerivedState} from "./pool/ICLPoolDerivedState.sol";
import {ICLPoolActions} from "./pool/ICLPoolActions.sol";
import {ICLPoolOwnerActions} from "./pool/ICLPoolOwnerActions.sol";
import {ICLPoolEvents} from "./pool/ICLPoolEvents.sol";

/// @title The interface for a CL Pool
/// @notice A CL pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface ICLPool is
    ICLPoolConstants,
    ICLPoolState,
    ICLPoolDerivedState,
    ICLPoolActions,
    ICLPoolEvents,
    ICLPoolOwnerActions
{}
