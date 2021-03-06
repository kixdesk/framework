# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

use Time::HiRes ();

# get needed objects
my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

=head1 ObjectLockState performance tests

This test script will create 10000 records in the object lock table,
and then perform SELECT and UPDATE queries on it to make sure that
they take not more than 0.5s (default config) each.

=cut

# get object lock state object
my $ObjectLockStateObject = $Kernel::OM->Get('Kernel::System::GenericInterface::ObjectLockState');

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

my $RandomNumber     = $Helper->GetRandomNumber();
my $CustomObjectType = "TestObject$RandomNumber";

my $TimeLimit = $ConfigObject->Get('GenericInterface::ObjectLockState::TimeLimit') || '0.5';
my $TestDataCount = 10_000;

# add config
my $WebserviceID = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice')->WebserviceAdd(
    Config => {
        Debugger => {
            DebugThreshold => 'debug',
        },
        Provider => {
            Transport => {
                Type => '',
            },
        },
    },
    Name    => "Test$RandomNumber",
    ValidID => 1,
    UserID  => 1,
);

$Self->True(
    $WebserviceID,
    "WebserviceAdd()",
);

my $Success;
for my $Count ( 1 .. $TestDataCount ) {

    # set initial
    $Success = $ObjectLockStateObject->ObjectLockStateSet(
        WebserviceID     => $WebserviceID,
        ObjectType       => $CustomObjectType,
        ObjectID         => $Count,
        LockState        => 'locked',
        LockStateCounter => 0,
    );

    if ( !$Success ) {
        $Self->True(
            $Success,
            "ObjectLockStateSet() for entry $Count",
        );
    }
}

for my $Count ( 1 .. 100 ) {
    my $TimeStart = [ Time::HiRes::gettimeofday() ];

    # try to access a random object's lock state
    my $LookFor = int( rand($TestDataCount) + 1 );

    # set initial
    my $ObjectLockState = $ObjectLockStateObject->ObjectLockStateGet(
        WebserviceID => $WebserviceID,
        ObjectType   => $CustomObjectType,
        ObjectID     => $LookFor,
    );

    my $TimeElapsed = Time::HiRes::tv_interval($TimeStart);

    $Self->True(
        $TimeElapsed < $TimeLimit,
        "ObjectLockStateGet() in $TestDataCount entries took less than $TimeLimit seconds (${TimeElapsed}s)",
    );

    $Self->Is(
        $ObjectLockState->{LockState},
        'locked',
        "ObjectLockStateGet() in $TestDataCount entries result",
    );

    $TimeStart = [ Time::HiRes::gettimeofday() ];

    # update
    $Success = $ObjectLockStateObject->ObjectLockStateSet(
        WebserviceID     => $WebserviceID,
        ObjectType       => $CustomObjectType,
        ObjectID         => $LookFor,
        LockState        => 'locked2',
        LockStateCounter => 0,
    );

    $TimeElapsed = Time::HiRes::tv_interval($TimeStart);

    $Self->True(
        $TimeElapsed < $TimeLimit,
        "ObjectLockStateSet in $TestDataCount entries took less than $TimeLimit seconds (${TimeElapsed}s)",
    );

    $ObjectLockState = $ObjectLockStateObject->ObjectLockStateGet(
        WebserviceID => $WebserviceID,
        ObjectType   => $CustomObjectType,
        ObjectID     => $LookFor,
    );

    $Self->Is(
        $ObjectLockState->{LockState},
        'locked2',
        "ObjectLockStateSet() in $TestDataCount entries result",
    );

    # restore old value update
    $Success = $ObjectLockStateObject->ObjectLockStateSet(
        WebserviceID     => $WebserviceID,
        ObjectType       => $CustomObjectType,
        ObjectID         => $LookFor,
        LockState        => 'locked',
        LockStateCounter => 0,
    );
}

# purge
$Success = $ObjectLockStateObject->ObjectLockStatePurge(
    WebserviceID => $WebserviceID,
);

$Self->True(
    $Success,
    'ObjectLockStatePurge() for existing entry',
);

# check
my $ObjectLockState = $ObjectLockStateObject->ObjectLockStateGet(
    WebserviceID => $WebserviceID,
    ObjectType   => $CustomObjectType,
    ObjectID     => $RandomNumber,
);

$Self->False(
    scalar %{$ObjectLockState},
    "ObjectLockStateGet() for deleted entry",
);

# check list
my $ObjectLockStates = $ObjectLockStateObject->ObjectLockStateList(
    WebserviceID => $WebserviceID,
    ObjectType   => $CustomObjectType,
    ObjectID     => $RandomNumber,
);

$Self->Is(
    scalar @{$ObjectLockStates},
    0,
    "ObjectLockStateList() for ObjectType",
);

# cleanup is done by RestoreDatabase.

1;
