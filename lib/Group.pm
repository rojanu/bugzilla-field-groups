# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Ali Ustek <AliUstek@gmail.com>

use strict;

package Bugzilla::Extension::FieldGroups::Group;

use base qw(Bugzilla::Object);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util;
use Scalar::Util qw(blessed);


###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'field_choice_group';
use constant LIST_ORDER => 'sortkey, name';

use constant DB_COLUMNS => qw(
    id
    field_id
    name
    sortkey
);

use constant UPDATE_COLUMNS => qw(
    name
    sortkey
);

use constant VALIDATORS => {
    name          => \&_check_name,
    sortkey	   => \&_check_sortkey,
};

###############################

sub new {
    my ($class, $param) = @_;
    my $dbh = Bugzilla->dbh;

    my $field;
    if (ref $param and !defined $param->{id}) {
        $field = $param->{field};
        my $name = $param->{name};
        if (!defined $field) {
            ThrowCodeError('bad_arg',
                {argument => 'field',
                 function => "${class}::new"});
        }
        if (!defined $name) {
            ThrowCodeError('bad_arg',
                {argument => 'name',
                 function => "${class}::new"});
        }

        my $condition = 'field_id = ? AND name = ?';
        my @values = ($field->id, $name);
        $param = { condition => $condition, values => \@values };
    }

    unshift @_, $param;
    my $group = $class->SUPER::new(@_);
    # Add the field object as attribute only if the field exists.
    $group->{field} = $field if ($group && $field);
    return $group;
}

sub create {
    my $class = shift;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    $class->check_required_create_fields(@_);
    my $params = $class->run_create_validators(@_);
    my $field = delete $params->{field};
    $params->{field_id} = $field->id;

    my $group = $class->insert_create_data($params);

    $dbh->bz_commit_transaction();
    return $group;
}


################################
# Validators
################################

sub _check_name {
    my ($invocant, $name, undef, $params) = @_;
    my $field = blessed($invocant) ? 
    									$invocant->field : $params->{field};

	$name = trim($name);
    $name || ThrowUserError('fieldgroup_undefined');
    if (length($name) > MAX_FIELD_VALUE_SIZE) {
        ThrowUserError('fieldgroup_name_too_long', { label => $name });
    }
    
    my $group = new Bugzilla::Extension::FieldGroups::Group({
                                         name => $name, 
                                         field  => $field,
                                    });
    if ($group && (!ref $invocant || $group->id != $invocant->id)) {
        ThrowUserError('fieldgroup_already_exists', {
        							group    => $group
                                });
    }

    return $name;
}

sub _check_sortkey {
    my ($invocant, $sortkey) = @_;
    
    $sortkey ||= 0;
    
    detaint_natural($sortkey) 
    || ThrowUserError('fieldgroup_sortkey_invalid', { sortkey => $sortkey });
    return $sortkey;
}

################################
# Accessors
################################

sub field_id { return $_[0]->{'field_id'}; }
sub name   { return $_[0]->{'name'}; }
sub sortkey { return $_[0]->{'sortkey'}; }

sub field {
    my $self = shift;
    if (!defined $self->{'field'}) {
        require Bugzilla::Field;
        $self->{'field'} = new Bugzilla::Field($self->field_id);
    }
    return $self->{'field'};
}

sub value_count {
    my $self = shift;
    return $self->{value_count} if defined $self->{value_count};
    my $fname = $self->field->name;
    my $dbh = Bugzilla->dbh;
    my $count = $dbh->selectrow_array( "SELECT COUNT(*) FROM $fname
                                                          WHERE group_id = ?", undef, $self->id);
    $self->{value_count} = $count;
    return $count;
}

sub group_values {
	my $self = shift;
	return $self->{group_values} if defined $self->{group_values};
	my $field = $self->field;
	my $fname = $self->field->name;
    my $dbh = Bugzilla->dbh;
    my $ids = $dbh->selectcol_arrayref("SELECT id FROM $fname
                                                          WHERE group_id = ?", undef, $self->id);
    $self->{group_values} = Bugzilla::Field::Choice->type($field)->new_from_list($ids);
    
    return $self->{group_values};
	
}

################################
# Methods
################################

sub set_name { $_[0]->set('name', $_[1]); }
sub set_sortkey { $_[0]->set('sortkey', $_[1]); }

###############################

1;

=head1 NAME

Bugzilla::Extension::FieldGroups::Group - A Group  for a <select>-type field value.

=head1 SYNOPSIS

 my $field = new Bugzilla::Field({name => 'bug_status'});

 my $group = new Bugzilla::Extension::FieldGroups::Group->new(1);

 my $groups = Bugzilla::Extension::FieldGroups::Group->new_from_list([1,2,3]);
 my $groups = Bugzilla::Extension::FieldGroups::Group->get_all();

=head1 DESCRIPTION

This is an implementation of L<Bugzilla::Object>, to represent option groups
in <select>-type fields

See the L</SYNOPSIS> for examples of how this works.
=head1 METHODS

=head2 Accessors

These are in addition to the standard L<Bugzilla::Object> accessors.

=over

=item C<value_count>

An integer count of the number of values that have this group set.

=back
