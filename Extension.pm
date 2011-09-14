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
# The Original Code is the FieldGroups CTC QueryBase Extension.
#
# The Initial Developer of the Original Code is Ali Ustek
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Ali Ustek <aliustek@gmail.com>

package Bugzilla::Extension::FieldGroups;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Token;

use Bugzilla::Extension::FieldGroups::Util;
use Bugzilla::Extension::FieldGroups::Group;

our $VERSION = '0.01';

BEGIN {
   *Bugzilla::Field::legal_groups = \&_legal_groups;
   *Bugzilla::Field::Choice::set_group = \&_set_group;
   *Bugzilla::Field::ChoiceInterface::group = \&_group;
}

#############################
#                   Database & Installation                   #
#############################

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    
    # Field Choice Group Information
    # -------------------------

    $args->{'schema'}->{'field_choice_group'} = {
        FIELDS => [
        	id            => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
            field_id   => {TYPE => 'INT3', NOTNULL => 1,
                                             REFERENCES => {TABLE  => 'fielddefs',
                                                                           COLUMN => 'id',
                                                                           DELETE => 'CASCADE'}},
            name      => {TYPE => 'varchar(64)', NOTNULL => 1},
            sortkey    => {TYPE => 'INT2', NOTNULL => 1, DEFAULT => 0},
        ],
        INDEXES => [
        	fieldchoicegroup_name_field_id_idx => 
                {FIELDS => [qw(field_id name)], TYPE => 'UNIQUE'},
            fieldchoicegroup_sortkey_idx => ['sortkey'],
        ],
    };
}

sub install_update_db {
    my ($self, $args) = @_;
    
    my $dbh = Bugzilla->dbh;
    my @standard_fields = 
        qw(bug_status resolution priority bug_severity op_sys rep_platform);
    my $custom_fields = $dbh->selectcol_arrayref(
        'SELECT name FROM fielddefs WHERE custom = 1 AND type IN(?,?)',
        undef, FIELD_TYPE_SINGLE_SELECT, FIELD_TYPE_MULTI_SELECT);
    foreach my $field_name (@standard_fields, @$custom_fields) {
    	if (!$dbh->bz_column_info($field_name, 'group_id')){
    	    my $field = new Bugzilla::Field({'name' => $field_name});
	        my $group = Bugzilla::Extension::FieldGroups::Group->create({
		        name   => "Default", 
        		field => $field,
		        sortkey => "0",
		    });
        	$dbh->bz_add_column($field_name, 'group_id', 
        												{TYPE => 'INT2'},
        												$group->id);
	        $dbh->bz_add_index($field_name, "${field_name}_group_id_idx", 
                           ['group_id']);
		}
    }
}

#############################
#                  Objects                                            #
#############################
sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};

    if ($class->isa('Bugzilla::Field::Choice')) {
        push(@$columns, 'group_id');
    }
}

sub object_before_create {
    my ($self, $args) = @_;
    my ($class, $params) = @$args{qw(class params)};
    if ($class->isa('Bugzilla::Field::Choice')) {
        my $input = Bugzilla->input_params;
        my $group = Bugzilla::Extension::FieldGroups::Group->new(
            																						$input->{'group_id'});
        $params->{group_id}   = $group->id;
    }
}

sub object_validators {
    my ($self, $args) = @_;
    my ($class, $validators) = @$args{qw(class validators)};

    if ($class->isa('Bugzilla::Field::Choice')) {
        $validators->{group_id} = \&_check_group_id;
    }
}

sub object_end_of_create {
    my ($self, $args) = @_;
    
    my $class  = $args->{'class'};
    my $object = $args->{'object'};

	if ($class->isa('Bugzilla::Field')) {
		my $created_group = Bugzilla::Extension::FieldGroups::Group->create({
            name   => "Default", 
            field => $class,
            sortkey => "0",
    	});
	}
}

sub object_update_columns {
    my ($self, $args) = @_;
    my ($object, $columns) = @$args{qw(object columns)};

    if ($object->isa('Bugzilla::Field::Choice')) {
        push(@$columns, 'group_id');
    }
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    my ($object) = $args->{object};
    if ($object->isa('Bugzilla::Field::Choice')) {
        my $input = Bugzilla->input_params;
        if ($object->{group_id} != $input->{'group_id'}) {
            my $group = Bugzilla::Extension::FieldGroups::Group->new(
            																						$input->{'group_id'});
        	$object->{group_id} = $group->id;
        }
    }
}

#############################
#              Bugzilla::Field Object Methods             #
#############################
sub _legal_groups {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

   if (!defined $self->{'legal_groups'}) {
        my $ids = $dbh->selectcol_arrayref(q{
            SELECT id FROM field_choice_group
             WHERE field_id = ?}, undef, $self->id);
 
        $self->{'legal_groups'} = 
        						Bugzilla::Extension::FieldGroups::Group->new_from_list($ids);
    }

    return $self->{'legal_groups'};
}

#############################
#      Bugzilla::Field::Choice Object Methods       #
#############################
sub _check_group_id {
    my ($invocant, $group_id) = @_;
    $group_id = trim($group_id);
    return undef if !$group_id;
    my $group_obj = 
    			Bugzilla::Extension::FieldGroups::Group->check({ id => $group_id });
    return $group_obj->id;
}

sub _set_group  {
    my ($self, $group) = @_;
    $self->set('group_id', $group);
    delete $self->{group};
}

##############################
# Bugzilla::Field::ChoiceInterface Object Methods #
##############################
sub _group {
    my $self = shift;
    if ($self->{group_id}) {
        require Bugzilla::Extension::FieldGroups::Group;
        $self->{group} ||= 
        					Bugzilla::Extension::FieldGroups::Group->new($self->{group_id});
    }
    return $self->{group};
}

#############################
#                          Pages                                       #
#############################
sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{page_id};
    my $vars = $args->{vars};
    
    if ($page =~ m{^fieldgroups.*}) {
    	#
    	# Preliminary checks:
    	#
    	my $user = Bugzilla->login(LOGIN_REQUIRED);
    	print Bugzilla->cgi->header();
    	
    	$vars->{'doc_section'} = 'edit-values.html';
    	
    	_field_group_actions($vars);
    	
    }
}

#############################
#                       Local Methods                             #
#############################
sub _display_field_groups {
    my $vars = shift;
    my $template = Bugzilla->template;
    $vars->{'groups'} = $vars->{'field'}->legal_groups;
    $template->process("fieldgroups/admin/group/list.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

sub _field_group_actions {
    my $vars = shift;
	my $template = Bugzilla->template;
	my $cgi = Bugzilla->cgi;
	
	Bugzilla->user->in_group('admin') ||
        ThrowUserError('auth_failure', {group  => "admin",
                                        action => "edit",
                                        object => "field_groups"});

    #
    # often-used variables
    #
    my $action = trim($cgi->param('action')  || '');
    my $token  = $cgi->param('token');

    #
    # field = '' -> Show nice list of fields
    #
    if (!$cgi->param('field')) {
        my @field_list =
            @{ Bugzilla->fields({ is_select => 1, is_abnormal => 0 }) };

        $vars->{'fields'} = \@field_list;
        $template->process("fieldgroups/admin/group/select-field.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        exit;
    }

    # At this point, the field must be defined.
    my $field = Bugzilla::Field->check($cgi->param('field'));
    if (!$field->is_select || $field->is_abnormal) {
        ThrowUserError('fieldname_invalid', { field => $field });
    }
    $vars->{'field'} = $field;

    #
    # action='' -> Show nice list of value groups.
    #
    _display_field_groups($vars) unless $action;

    #
    # action='add' -> show form for adding new field group.
    # (next action will be 'new')
    #
    if ($action eq 'add') {
        $vars->{'token'} = issue_session_token('add_field_group');
        $template->process("fieldgroups/admin/group/create.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        exit;
    }

    #
    # action='new' -> add field group entered in the 'action=add' screen
    #
    if ($action eq 'new') {
        check_token_data($token, 'add_field_group');

        my $created_group = Bugzilla::Extension::FieldGroups::Group->create({
            name   => scalar $cgi->param('group'), 
            field => $field,
            sortkey => scalar $cgi->param('sortkey'),
        });

        delete_token($token);

        $vars->{'message'} = 'field_group_created';
        $vars->{'group'} = $created_group;
        _display_field_groups($vars);
    }

    # After this, we always have a group
    my $group = Bugzilla::Extension::FieldGroups::Group->check({field => $field,
                                                                                 name => $cgi->param('group')});
    $vars->{'group'} = $group;

    #
    # action='del' -> ask if user really wants to delete
    # (next action would be 'delete')
    #
    if ($action eq 'del') {
        $vars->{'token'} = issue_session_token('delete_field_group');

        $template->process("fieldgroups/admin/group/confirm-delete.html.tmpl", $vars)
          || ThrowTemplateError($template->error());

        exit;
    }


    #
    # action='delete' -> really delete the field group
    #
    if ($action eq 'delete') {
        check_token_data($token, 'delete_field_group');
        $group->remove_from_db();
        delete_token($token);
        $vars->{'message'} = 'field_group_deleted';
        $vars->{'no_edit_link'} = 1;
        _display_field_groups($vars);
    }


    #
    # action='edit' -> present the edit-group form
    # (next action would be 'update')
    #
    if ($action eq 'edit') {
        $vars->{'token'} = issue_session_token('edit_field_group');
        $template->process("fieldgroups/admin/group/edit.html.tmpl", $vars)
          || ThrowTemplateError($template->error());

        exit;
    }


    #
    # action='update' -> update the field group
    #
    if ($action eq 'update') {
        check_token_data($token, 'edit_field_group');
        $vars->{'group_old'} = $group->name;
        $group->set_name($cgi->param('group_new'));
        $group->set_sortkey($cgi->param('sortkey'));
        $vars->{'changes'} = $group->update();
        delete_token($token);
        $vars->{'message'} = 'field_group_updated';
        _display_field_groups($vars);
    }

    # No valid action found
    ThrowUserError('unknown_action', {action => $action});
}

__PACKAGE__->NAME;

=head1 NAME

Bugzilla::Extension::FieldGroups - Object for a Bugzilla FieldGroups extension.

=head1 SYNOPSIS

    my @legal_groups  = $field->legal_groups();

=head1 DESCRIPTION

This package will add optgroup support to <select>-fields.

The methods that are added to other Bugzilla classes are listed below.

=head2 Custom Added Methods

=item C<legal_groups()>
 Description: Valid value groups for this field, as an array of 
                     L<Bugzilla::Extension::FieldGroups::Group> objects.
 Params:      none.
 Returns:     An array of L<Bugzilla::Extension::FieldGroups::Group> objects.
 
 =item C<check_group_id()>
 Description: Validate group id 
 Params:      Group id.
 Returns:     Validated group id.
 
 =item C<set_group()>
 Description: Sets group for the current Bigzilla::Field::Choice.
 Params:      L<Bugzilla::Extension::ChoiceGroups::Group>.
 Returns:     nothing.

 =item C<group()>
 Description: Gets group for the current L<Bugzilla::Field::Choice>.
 Params:      none
 Returns:     L<Bugzilla::Extension::ChoiceGroups::Group> of current 
                   L<Bugzilla::Field::Choice>.
 
=back

=head1 SEE ALSO

L<Bugzilla::Field>
