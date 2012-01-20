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
use Bugzilla::Extension::FieldGroups::Optgroup;

our $VERSION = '0.01';

BEGIN {
   *Bugzilla::Field::legal_optgroups = \&_legal_optgroups;
   *Bugzilla::Field::Choice::set_optgroup = \&_set_optgroup;
   *Bugzilla::Field::ChoiceInterface::optgroup = \&_optgroup;
}

#############################
#                   Database & Installation                   #
#############################

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    
    # Field Choice Optgroup Information
    # -------------------------

    $args->{'schema'}->{'field_choice_optgroup'} = {
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
        	fieldchoiceoptgroup_name_field_id_idx => 
                {FIELDS => [qw(field_id name)], TYPE => 'UNIQUE'},
            fieldchoiceoptgroup_sortkey_idx => ['sortkey'],
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
    	if (!$dbh->bz_column_info($field_name, 'optgroup_id')){
    	    my $field = new Bugzilla::Field({'name' => $field_name});
	        my $optgroup = Bugzilla::Extension::FieldGroups::Optgroup->create({
		        name   => "Default", 
        		field => $field,
		        sortkey => "0",
		    });
        	$dbh->bz_add_column($field_name, 'optgroup_id', 
        												{TYPE => 'INT2'},
        												$optgroup->id);
	        $dbh->bz_add_index($field_name, "${field_name}_optgroup_id_idx", 
                           ['optgroup_id']);
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
        push(@$columns, 'optgroup_id');
    }
}

sub object_before_create {
    my ($self, $args) = @_;
    my ($class, $params) = @$args{qw(class params)};
    if ($class->isa('Bugzilla::Field::Choice')) {
        my $input = Bugzilla->input_params;
        my $optgroup = Bugzilla::Extension::FieldGroups::Optgroup->new($input->{'optgroup_id'});
        $params->{optgroup_id}   = $optgroup->id;
    }
}

sub object_validators {
    my ($self, $args) = @_;
    my ($class, $validators) = @$args{qw(class validators)};

    if ($class->isa('Bugzilla::Field::Choice')) {
        $validators->{optgroup_id} = \&_check_optgroup_id;
    }
}

sub object_end_of_create {
    my ($self, $args) = @_;
    
    my $class  = $args->{'class'};
    my $object = $args->{'object'};

	if ($class->isa('Bugzilla::Field')) {
		my $created_optgroup = Bugzilla::Extension::FieldGroups::Optgroup->create({
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
        push(@$columns, 'optgroup_id');
    }
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    my ($object) = $args->{object};
    if ($object->isa('Bugzilla::Field::Choice')) {
        my $input = Bugzilla->input_params;
        if ($object->{optgroup_id} != $input->{'optgroup_id'}) {
            my $optgroup = Bugzilla::Extension::FieldGroups::Optgroup->new($input->{'optgroup_id'});
        	$object->{optgroup_id} = $optgroup->id;
        }
    }
}

#############################
#              Bugzilla::Field Object Methods             #
#############################
sub _legal_optgroups {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

   if (!defined $self->{'legal_optgroups'}) {
        my $ids = $dbh->selectcol_arrayref(q{
            SELECT id FROM field_choice_optgroup
             WHERE field_id = ?}, undef, $self->id);
 
        $self->{'legal_optgroups'} = 
        						Bugzilla::Extension::FieldGroups::Optgroup->new_from_list($ids);
    }

    return $self->{'legal_optgroups'};
}

#############################
#      Bugzilla::Field::Choice Object Methods       #
#############################
sub _check_optgroup_id {
    my ($invocant, $optgroup_id) = @_;
    $optgroup_id = trim($optgroup_id);
    return undef if !$optgroup_id;
    my $optgroup_obj = 
    			Bugzilla::Extension::FieldGroups::Optgroup->check({ id => $optgroup_id });
    return $optgroup_obj->id;
}

sub _set_optgroup  {
    my ($self, $optgroup) = @_;
    $self->set('optgroup_id', $optgroup);
    delete $self->{optgroup};
}

##############################
# Bugzilla::Field::ChoiceInterface Object Methods #
##############################
sub _optgroup {
    my $self = shift;
    if ($self->{optgroup_id}) {
        require Bugzilla::Extension::FieldGroups::Optgroup;
        $self->{optgroup} ||= 
                Bugzilla::Extension::FieldGroups::Optgroup->new($self->{optgroup_id});
    }
    return $self->{optgroup};
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
    	
    	_field_optgroup_actions($vars);
    	
    }
}

#############################
#                       Local Methods                             #
#############################
sub _display_field_optgroups {
    my $vars = shift;
    my $template = Bugzilla->template;
    $vars->{'optgroups'} = $vars->{'field'}->legal_optgroups;
    $template->process("fieldgroups/admin/group/list.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

sub _field_optgroup_actions {
    my $vars = shift;
	my $template = Bugzilla->template;
	my $cgi = Bugzilla->cgi;
	
	Bugzilla->user->in_group('admin') ||
        ThrowUserError('auth_failure', {group  => "admin",
                                        action => "edit",
                                        object => "field_optgroups"});

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
    # action='' -> Show nice list of value optgroups.
    #
    _display_field_optgroups($vars) unless $action;

    #
    # action='add' -> show form for adding new field optgroup.
    # (next action will be 'new')
    #
    if ($action eq 'add') {
        $vars->{'token'} = issue_session_token('add_field_optgroup');
        $template->process("fieldgroups/admin/group/create.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        exit;
    }

    #
    # action='new' -> add field optgroup entered in the 'action=add' screen
    #
    if ($action eq 'new') {
        check_token_data($token, 'add_field_optgroup');

        my $created_optgroup = Bugzilla::Extension::FieldGroups::Optgroup->create({
            name   => scalar $cgi->param('optgroup'), 
            field => $field,
            sortkey => scalar $cgi->param('sortkey'),
        });

        delete_token($token);

        $vars->{'message'} = 'field_optgroup_created';
        $vars->{'optgroup'} = $created_optgroup;
        _display_field_optgroups($vars);
    }

    # After this, we always have a optgroup
    my $optgroup = Bugzilla::Extension::FieldGroups::Optgroup->check(
                                             {field => $field,
                                              name => $cgi->param('optgroup')});
    $vars->{'optgroup'} = $optgroup;

    #
    # action='del' -> ask if user really wants to delete
    # (next action would be 'delete')
    #
    if ($action eq 'del') {
        $vars->{'token'} = issue_session_token('delete_field_optgroup');

        $template->process("fieldgroups/admin/group/confirm-delete.html.tmpl", $vars)
          || ThrowTemplateError($template->error());

        exit;
    }


    #
    # action='delete' -> really delete the field optgroup
    #
    if ($action eq 'delete') {
        check_token_data($token, 'delete_field_optgroup');
        $optgroup->remove_from_db();
        delete_token($token);
        $vars->{'message'} = 'field_optgroup_deleted';
        $vars->{'no_edit_link'} = 1;
        _display_field_optgroups($vars);
    }


    #
    # action='edit' -> present the edit-optgroup form
    # (next action would be 'update')
    #
    if ($action eq 'edit') {
        $vars->{'token'} = issue_session_token('edit_field_optgroup');
        $template->process("fieldgroups/admin/group/edit.html.tmpl", $vars)
          || ThrowTemplateError($template->error());

        exit;
    }


    #
    # action='update' -> update the field optgroup
    #
    if ($action eq 'update') {
        check_token_data($token, 'edit_field_optgroup');
        $vars->{'optgroup_old'} = $optgroup->name;
        $optgroup->set_name($cgi->param('optgroup_new'));
        $optgroup->set_sortkey($cgi->param('sortkey'));
        $vars->{'changes'} = $optgroup->update();
        delete_token($token);
        $vars->{'message'} = 'field_optgroup_updated';
        _display_field_optgroups($vars);
    }

    # No valid action found
    ThrowUserError('unknown_action', {action => $action});
}

__PACKAGE__->NAME;

=head1 NAME

Bugzilla::Extension::FieldGroups - Object for a Bugzilla FieldGroups extension.

=head1 SYNOPSIS

    my @legal_optgroups  = $field->legal_optgroups();

=head1 DESCRIPTION

This package will add optoptgroup support to <select>-fields.

The methods that are added to other Bugzilla classes are listed below.

=head2 Custom Added Methods

=item C<legal_optgroups()>
 Description: Valid value optgroups for this field, as an array of 
                     L<Bugzilla::Extension::FieldGroups::Optgroup> objects.
 Params:      none.
 Returns:     An array of L<Bugzilla::Extension::FieldGroups::Optgroup> objects.
 
 =item C<check_optgroup_id()>
 Description: Validate optgroup id 
 Params:      Optgroup id.
 Returns:     Validated optgroup id.
 
 =item C<set_optgroup()>
 Description: Sets optgroup for the current Bigzilla::Field::Choice.
 Params:      L<Bugzilla::Extension::ChoiceGroups::Optgroup>.
 Returns:     nothing.

 =item C<optgroup()>
 Description: Gets optgroup for the current L<Bugzilla::Field::Choice>.
 Params:      none
 Returns:     L<Bugzilla::Extension::ChoiceGroups::Optgroup> of current 
                   L<Bugzilla::Field::Choice>.
 
=back

=head1 SEE ALSO

L<Bugzilla::Field>
