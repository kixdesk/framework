# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentLinkObject;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ( $Self->{Subaction} eq 'UpdateComplextTablePreferences' ) {

        # save user preferences (shown columns)

        # Needed objects
        my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
        my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $SourceObject      = $ParamObject->GetParam( Param => 'SourceObject' )      || '';
        my $DestinationObject = $ParamObject->GetParam( Param => 'DestinationObject' ) || '';

        my $Success = $LayoutObject->ComplexTablePreferencesSet(
            DestinationObject => $DestinationObject,
        );

        if ( !$Success ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "System was unable to update preferences!",
            );
            return;
        }

        # get linked objects
        my $LinkListWithData = $Kernel::OM->Get('Kernel::System::LinkObject')->LinkListWithData(
            Object           => $SourceObject,
            Object2          => $DestinationObject,
            Key              => $Self->{TicketID},
            State            => 'Valid',
            UserID           => $Self->{UserID},
            ObjectParameters => {
                Ticket => {
                    IgnoreLinkedTicketStateTypes => 1,
                },
            },
        );

        # create the link table
        my $LinkTableStrg = $LayoutObject->LinkObjectTableCreate(
            LinkListWithData => $LinkListWithData,
            ViewMode         => 'Complex',           # only make sense for complex
            Object           => $SourceObject,
            Key              => $Self->{TicketID},
            AJAX             => 1,
        );

        return $LayoutObject->Attachment(
            ContentType => 'text/html',
            Content     => $LinkTableStrg,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # ------------------------------------------------------------ #
    # close
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Close' ) {
        return $LayoutObject->PopupClose(
            Reload => 1,
        );
    }

    # get params
    my %Form;
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    $Form{SourceObject} = $ParamObject->GetParam( Param => 'SourceObject' );
    $Form{SourceKey}    = $ParamObject->GetParam( Param => 'SourceKey' );
    $Form{Mode}         = $ParamObject->GetParam( Param => 'Mode' ) || 'Normal';

    # check needed stuff
    if ( !$Form{SourceObject} || !$Form{SourceKey} ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('Need SourceObject and SourceKey!'),
            Comment => Translatable('Please contact the admin.'),
        );
    }

    my $LinkObject = $Kernel::OM->Get('Kernel::System::LinkObject');

    # check if this is a temporary ticket link used while creating a new ticket
    my $TemporarySourceTicketLink;
    if (
        $Form{Mode} eq 'Temporary'
        && $Form{SourceObject} eq 'Ticket'
        && $Form{SourceKey} =~ m{ \A \d+ \. \d+ }xms
        )
    {
        $TemporarySourceTicketLink = 1;
    }

    # do the permission check only if it is no temporary ticket link used while creating a new ticket
    if ( !$TemporarySourceTicketLink ) {

        # permission check
        my $Permission = $LinkObject->ObjectPermission(
            Object => $Form{SourceObject},
            Key    => $Form{SourceKey},
            UserID => $Self->{UserID},
        );

        if ( !$Permission ) {
            return $LayoutObject->NoPermission(
                Message    => Translatable('You need ro permission!'),
                WithHeader => 'yes',
            );
        }
    }

    # get form params
    $Form{TargetIdentifier} = $ParamObject->GetParam( Param => 'TargetIdentifier' )
        || $Form{SourceObject};

    # investigate the target object
    if ( $Form{TargetIdentifier} =~ m{ \A ( .+? ) :: ( .+ ) \z }xms ) {
        $Form{TargetObject}    = $1;
        $Form{TargetSubObject} = $2;
    }
    else {
        $Form{TargetObject} = $Form{TargetIdentifier};
    }

    # get possible objects list
    my %PossibleObjectsList = $LinkObject->PossibleObjectsList(
        Object => $Form{SourceObject},
        UserID => $Self->{UserID},
    );

    # check if target object is a possible object to link with the source object
    if ( !$PossibleObjectsList{ $Form{TargetObject} } ) {
        my @PossibleObjects = sort { lc $a cmp lc $b } keys %PossibleObjectsList;
        $Form{TargetObject} = $PossibleObjects[0];
    }

    # set mode params
    if ( $Form{Mode} eq 'Temporary' ) {
        $Form{State} = 'Temporary';
    }
    else {
        $Form{Mode}  = 'Normal';
        $Form{State} = 'Valid';
    }

    # get source object description
    my %SourceObjectDescription = $LinkObject->ObjectDescriptionGet(
        Object => $Form{SourceObject},
        Key    => $Form{SourceKey},
        Mode   => $Form{Mode},
        UserID => $Self->{UserID},
    );

    # ------------------------------------------------------------ #
    # link delete
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'LinkDelete' ) {

        # output header
        my $Output = $LayoutObject->Header( Type => 'Small' );

        if ( $ParamObject->GetParam( Param => 'SubmitDelete' ) ) {

            # challenge token check for write action
            $LayoutObject->ChallengeTokenCheck();

            # delete all temporary links older than one day
            $LinkObject->LinkCleanup(
                State  => 'Temporary',
                Age    => ( 60 * 60 * 24 ),
                UserID => $Self->{UserID},
            );

            # get the link delete keys and target object
            my @LinkDeleteIdentifier = $ParamObject->GetArray(
                Param => 'LinkDeleteIdentifier',
            );

            # delete links from database
            IDENTIFIER:
            for my $Identifier (@LinkDeleteIdentifier) {

                my @Target = $Identifier =~ m{^ ( [^:]+? ) :: (.+?) :: ( [^:]+? ) $}smx;

                next IDENTIFIER if !$Target[0];    # TargetObject
                next IDENTIFIER if !$Target[1];    # TargetKey
                next IDENTIFIER if !$Target[2];    # LinkType

                my $DeletePermission = $LinkObject->ObjectPermission(
                    Object => $Target[0],
                    Key    => $Target[1],
                    UserID => $Self->{UserID},
                );

                next IDENTIFIER if !$DeletePermission;

                # delete link from database
                my $Success = $LinkObject->LinkDelete(
                    Object1 => $Form{SourceObject},
                    Key1    => $Form{SourceKey},
                    Object2 => $Target[0],
                    Key2    => $Target[1],
                    Type    => $Target[2],
                    UserID  => $Self->{UserID},
                );

                next IDENTIFIER if $Success;

                # get target object description
                my %TargetObjectDescription = $LinkObject->ObjectDescriptionGet(
                    Object => $Target[0],
                    Key    => $Target[1],
                    Mode   => $Form{Mode},
                    UserID => $Self->{UserID},
                );

                # output an error notification
                $Output .= $LayoutObject->Notify(
                    Priority => 'Error',
                    Data     => $LayoutObject->{LanguageObject}->Translate(
                        "Can not delete link with %s!",
                        $TargetObjectDescription{Normal},
                    ),
                );
            }
        }

        # output link delete block
        $LayoutObject->Block(
            Name => 'Delete',
            Data => {
                %Form,
                SourceObjectNormal => $SourceObjectDescription{Normal},
            },
        );

        # output special block for temporary links
        # to close the popup without reloading the parent window
        if ( $Form{Mode} eq 'Temporary' ) {

            $LayoutObject->Block(
                Name => 'LinkDeleteTemporaryLink',
                Data => {},
            );
        }

        # get already linked objects
        my $LinkListWithData = $LinkObject->LinkListWithData(
            Object => $Form{SourceObject},
            Key    => $Form{SourceKey},
            State  => $Form{State},
            UserID => $Self->{UserID},
        );

        # redirect to overview if list is empty
        if ( !$LinkListWithData || !%{$LinkListWithData} ) {
            return $LayoutObject->Redirect(
                OP => "Action=$Self->{Action};Mode=$Form{Mode}"
                    . ";SourceObject=$Form{SourceObject};SourceKey=$Form{SourceKey}"
                    . ";TargetIdentifier=$Form{TargetIdentifier}",
            );
        }

        # create the link table
        my $LinkTableStrg = $LayoutObject->LinkObjectTableCreateComplex(
            LinkListWithData => $LinkListWithData,
            ViewMode         => 'ComplexDelete',
        );

        # output the link table
        $LayoutObject->Block(
            Name => 'DeleteTableComplex',
            Data => {
                LinkTableStrg => $LinkTableStrg,
            },
        );

        # start template output
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AgentLinkObject',
        );

        $Output .= $LayoutObject->Footer( Type => 'Small' );

        return $Output;
    }

    # ------------------------------------------------------------ #
    # overview
    # ------------------------------------------------------------ #
    else {

        # get the type
        my $TypeIdentifier = $ParamObject->GetParam( Param => 'TypeIdentifier' );

        # output header
        my $Output = $LayoutObject->Header( Type => 'Small' );

        # add new links
        if ( $ParamObject->GetParam( Param => 'SubmitLink' ) ) {

            # challenge token check for write action
            $LayoutObject->ChallengeTokenCheck();

            # get the link target keys
            my @LinkTargetKeys = $ParamObject->GetArray( Param => 'LinkTargetKeys' );

            # get all links that the source object already has
            my $LinkList = $LinkObject->LinkList(
                Object => $Form{SourceObject},
                Key    => $Form{SourceKey},
                State  => $Form{State},
                UserID => $Self->{UserID},
            );

            # split the identifier
            my @Type = split q{::}, $TypeIdentifier;

            if ( $Type[0] && $Type[1] && ( $Type[1] eq 'Source' || $Type[1] eq 'Target' ) ) {

                # add links
                TARGETKEYORG:
                for my $TargetKeyOrg (@LinkTargetKeys) {

                    TYPE:
                    for my $LType ( sort keys %{ $LinkList->{ $Form{TargetObject} } } ) {

                        # extract source and target
                        my $Source = $LinkList->{ $Form{TargetObject} }->{$LType}->{Source} ||= {};
                        my $Target = $LinkList->{ $Form{TargetObject} }->{$LType}->{Target} ||= {};

                        # check if source and target object are already linked
                        next TYPE
                            if !$Source->{$TargetKeyOrg} && !$Target->{$TargetKeyOrg};

                        # next type, if link already exists
                        if ( $LType eq $Type[0] ) {
                            next TYPE if $Type[1] eq 'Source' && $Source->{$TargetKeyOrg};
                            next TYPE if $Type[1] eq 'Target' && $Target->{$TargetKeyOrg};
                        }

                        # check the type groups
                        my $TypeGroupCheck = $LinkObject->PossibleType(
                            Type1  => $Type[0],
                            Type2  => $LType,
                            UserID => $Self->{UserID},
                        );

                        next TYPE if $TypeGroupCheck && $Type[0] ne $LType;

                        # get target object description
                        my %TargetObjectDescription = $LinkObject->ObjectDescriptionGet(
                            Object => $Form{TargetObject},
                            Key    => $TargetKeyOrg,
                            UserID => $Self->{UserID},
                        );

                        # lookup type id
                        my $TypeID = $LinkObject->TypeLookup(
                            Name   => $LType,
                            UserID => $Self->{UserID},
                        );

                        # get type data
                        my %TypeData = $LinkObject->TypeGet(
                            TypeID => $TypeID,
                            UserID => $Self->{UserID},
                        );

                        # investigate type name
                        my $TypeName = $TypeData{SourceName};
                        if ( $Target->{$TargetKeyOrg} ) {
                            $TypeName = $TypeData{TargetName};
                        }

                        # translate the type name
                        $TypeName = $LayoutObject->{LanguageObject}->Translate($TypeName);

                        # output an error notification
                        $Output .= $LayoutObject->Notify(
                            Priority => 'Error',
                            Data     => $LayoutObject->{LanguageObject}->Translate(
                                'Can not create link with %s! Object already linked as %s.',
                                $TargetObjectDescription{Normal},
                                $TypeName,
                            ),
                        );

                        next TARGETKEYORG;
                    }

                    my $SourceObject = $Form{TargetObject};
                    my $SourceKey    = $TargetKeyOrg;
                    my $TargetObject = $Form{SourceObject};
                    my $TargetKey    = $Form{SourceKey};

                    if ( $Type[1] eq 'Target' ) {
                        $SourceObject = $Form{SourceObject};
                        $SourceKey    = $Form{SourceKey};
                        $TargetObject = $Form{TargetObject};
                        $TargetKey    = $TargetKeyOrg;
                    }

                    # check if this is a temporary ticket link used while creating a new ticket
                    my $TemporaryTargetTicketLink;
                    if (
                        $Form{Mode} eq 'Temporary'
                        && $TargetObject eq 'Ticket'
                        && $TargetKey =~ m{ \A \d+ \. \d+ }xms
                        )
                    {
                        $TemporaryTargetTicketLink = 1;
                    }

                    # do the permission check only if it is no temporary ticket link
                    # used while creating a new ticket
                    if ( !$TemporaryTargetTicketLink ) {

                        my $AddPermission = $LinkObject->ObjectPermission(
                            Object => $TargetObject,
                            Key    => $TargetKey,
                            UserID => $Self->{UserID},
                        );

                        next TARGETKEYORG if !$AddPermission;
                    }

                    # add links to database
                    my $Success = $LinkObject->LinkAdd(
                        SourceObject => $SourceObject,
                        SourceKey    => $SourceKey,
                        TargetObject => $TargetObject,
                        TargetKey    => $TargetKey,
                        Type         => $Type[0],
                        State        => $Form{State},
                        UserID       => $Self->{UserID},
                    );

                    next TARGETKEYORG if $Success;

                    # get target object description
                    my %TargetObjectDescription = $LinkObject->ObjectDescriptionGet(
                        Object => $Form{TargetObject},
                        Key    => $TargetKeyOrg,
                        UserID => $Self->{UserID},
                    );

                    # output an error notification
                    $Output .= $LayoutObject->Notify(
                        Priority => 'Error',
                        Data     => $LayoutObject->{LanguageObject}->Translate(
                            "Can not create link with %s!",
                            $TargetObjectDescription{Normal}
                        ),
                    );
                }
            }
        }

        # get the selectable object list
        my $TargetObjectStrg = $LayoutObject->LinkObjectSelectableObjectList(
            Object   => $Form{SourceObject},
            Selected => $Form{TargetIdentifier},
        );

        # check needed stuff
        if ( !$TargetObjectStrg ) {
            return $LayoutObject->ErrorScreen(
                Message => $LayoutObject->{LanguageObject}
                    ->Translate( 'The object %s cannot link with other object!', $Form{SourceObject} ),
                Comment => Translatable('Please contact the admin.'),
            );
        }

        # output link block
        $LayoutObject->Block(
            Name => 'Link',
            Data => {
                %Form,
                SourceObjectNormal => $SourceObjectDescription{Normal},
                SourceObjectLong   => $SourceObjectDescription{Long},
                TargetObjectStrg   => $TargetObjectStrg,
            },
        );

        # output special block for temporary links
        # to close the popup without reloading the parent window
        if ( $Form{Mode} eq 'Temporary' ) {

            $LayoutObject->Block(
                Name => 'LinkAddTemporaryLink',
                Data => {},
            );
        }

        # get search option list
        my @SearchOptionList = $LayoutObject->LinkObjectSearchOptionList(
            Object    => $Form{TargetObject},
            SubObject => $Form{TargetSubObject},
        );

        # output search option fields
        for my $Option (@SearchOptionList) {

            # output link search row block
            $LayoutObject->Block(
                Name => 'LinkSearchRow',
                Data => $Option,
            );
        }

        # create the search param hash
        my %SearchParam;
        OPTION:
        for my $Option (@SearchOptionList) {

            next OPTION if !$Option->{FormData};
            next OPTION if $Option->{FormData}
                && ref $Option->{FormData} eq 'ARRAY' && !@{ $Option->{FormData} };

            $SearchParam{ $Option->{Key} } = $Option->{FormData};
        }

        # start search
        my $SearchList;
        if (
            %SearchParam
            || $Kernel::OM->Get('Kernel::Config')->Get('Frontend::AgentLinkObject::WildcardSearch')
            )
        {

            $SearchList = $LinkObject->ObjectSearch(
                Object       => $Form{TargetObject},
                SubObject    => $Form{TargetSubObject},
                SearchParams => \%SearchParam,
                UserID       => $Self->{UserID},
            );
        }

        # remove the source object from the search list
        if ( $SearchList && $SearchList->{ $Form{SourceObject} } ) {

            for my $LinkType ( sort keys %{ $SearchList->{ $Form{SourceObject} } } ) {

                # extract link type List
                my $LinkTypeList = $SearchList->{ $Form{SourceObject} }->{$LinkType};

                for my $Direction ( sort keys %{$LinkTypeList} ) {

                    # remove the source key
                    delete $LinkTypeList->{$Direction}->{ $Form{SourceKey} };
                }
            }
        }

        # get already linked objects
        my $LinkListWithData = $LinkObject->LinkListWithData(
            Object => $Form{SourceObject},
            Key    => $Form{SourceKey},
            State  => $Form{State},
            UserID => $Self->{UserID},
        );

        if ( $LinkListWithData && $LinkListWithData->{ $Form{TargetObject} } ) {

            # build object id lookup hash from search list
            my %SearchListObjectKeys;
            for my $Key (
                sort keys %{ $SearchList->{ $Form{TargetObject} }->{NOTLINKED}->{Source} }
                )
            {
                $SearchListObjectKeys{$Key} = 1;
            }

            # check if linked objects are part of the search list
            for my $LinkType ( sort keys %{ $LinkListWithData->{ $Form{TargetObject} } } ) {

                # extract link type List
                my $LinkTypeList = $LinkListWithData->{ $Form{TargetObject} }->{$LinkType};

                for my $Direction ( sort keys %{$LinkTypeList} ) {

                    # extract the keys
                    KEY:
                    for my $Key ( sort keys %{ $LinkTypeList->{$Direction} } ) {

                        next KEY if $SearchListObjectKeys{$Key};

                        # delete from linked objects list if key is not in search list
                        delete $LinkTypeList->{$Direction}->{$Key};
                    }
                }
            }
        }

        # output delete link
        if ( $LinkListWithData && %{$LinkListWithData} ) {

            # output the link menu delete block
            $LayoutObject->Block(
                Name => 'LinkMenuDelete',
                Data => \%Form,
            );
        }

        # add search result to link list
        if ( $SearchList && $SearchList->{ $Form{TargetObject} } ) {
            $LinkListWithData->{ $Form{TargetObject} }->{NOTLINKED} = $SearchList->{ $Form{TargetObject} }->{NOTLINKED};
        }

        # get possible types list
        my %PossibleTypesList = $LinkObject->PossibleTypesList(
            Object1 => $Form{SourceObject},
            Object2 => $Form{TargetObject},
            UserID  => $Self->{UserID},
        );

        # define blank line entry
        my %BlankLine = (
            Key      => '-',
            Value    => '-------------------------',
            Disabled => 1,
        );

        # create the selectable type list
        my $Counter = 0;
        my @SelectableTypesList;
        POSSIBLETYPE:
        for my $PossibleType ( sort { lc $a cmp lc $b } keys %PossibleTypesList ) {

            # lookup type id
            my $TypeID = $LinkObject->TypeLookup(
                Name   => $PossibleType,
                UserID => $Self->{UserID},
            );

            # get type
            my %Type = $LinkObject->TypeGet(
                TypeID => $TypeID,
                UserID => $Self->{UserID},
            );

            # create the source name
            my %SourceName;
            $SourceName{Key}   = $PossibleType . '::Source';
            $SourceName{Value} = $Type{SourceName};

            push @SelectableTypesList, \%SourceName;

            next POSSIBLETYPE if !$Type{Pointed};

            # create the target name
            my %TargetName;
            $TargetName{Key}   = $PossibleType . '::Target';
            $TargetName{Value} = $Type{TargetName};

            push @SelectableTypesList, \%TargetName;
        }
        continue {

            # add blank line
            push @SelectableTypesList, \%BlankLine;

            $Counter++;
        }

        # removed last (empty) entry
        pop @SelectableTypesList;

        # add blank lines on top and bottom of the list if more then two linktypes
        if ( $Counter > 2 ) {
            unshift @SelectableTypesList, \%BlankLine;
            push @SelectableTypesList, \%BlankLine;
        }

        # create link type string
        my $LinkTypeStrg = $LayoutObject->BuildSelection(
            Data       => \@SelectableTypesList,
            Name       => 'TypeIdentifier',
            SelectedID => $TypeIdentifier || 'Normal::Source',
            Class      => 'Modernize',
        );

        # create the link table
        my $LinkTableStrg = $LayoutObject->LinkObjectTableCreateComplex(
            LinkListWithData => {
                $Form{TargetObject} => $LinkListWithData->{ $Form{TargetObject} },
            },
            ViewMode     => 'ComplexAdd',
            LinkTypeStrg => $LinkTypeStrg,
        );

        # output the link table
        $LayoutObject->Block(
            Name => 'LinkTableComplex',
            Data => {
                LinkTableStrg => $LinkTableStrg,
            },
        );

        # start template output
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AgentLinkObject',
        );

        $Output .= $LayoutObject->Footer( Type => 'Small' );

        return $Output;
    }
}

1;