=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package HiveLoadGIFTS_conf;

use warnings;
use strict;
use feature 'say';
use File::Spec::Functions;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');
use base ('Bio::EnsEMBL::Analysis::Hive::Config::HiveBaseConfig_conf');

use Bio::EnsEMBL::ApiVersion qw/software_version/;

sub default_options {
  my ($self) = @_;
  return {
    # inherit other stuff from the base class
	  %{ $self->SUPER::default_options() },

'output_dir' => '',

'pipeline_name' => 'gifts_loading',
'pipeline_comment_perfect_match' => 'Perfect matches between Ensembl and UniProt proteins.',
'pipeline_comment_blast_cigar' => 'Blasts and cigars between Ensembl and UniProt proteins.',

'enscode_root_dir' => '/path/to/enscode/',
'userstamp' => 'ensembl_gifts_loading_pipeline', # username to be registered as the one loading the Ensembl data
#'user_r' => '', # read-only user
'user_w' => '', # write user
'password' => '', # write password
'driver' => 'mysql',

'import_species_script' => $self->o('enscode_root_dir').'/GIFTS/scripts/ensembl_import_species_data.pl', # no need to modify this
'perfect_match_script' => $self->o('enscode_root_dir').'/GIFTS/scripts/eu_alignment_perfect_match.pl',   # no need to modify this
'blast_cigar_script' => $self->o('enscode_root_dir').'/GIFTS/scripts/eu_alignment_blast_cigar.pl',       # no need to modify this

'species' => 'homo_sapiens',
'registry_host' => '',
'registry_user' => '',
'registry_pass' => '',
'registry_port' => '',

'release_mapping_history_id' => 0,
'uniprot_sp_file' => '',
'uniprot_sp_isoform_file' => '',
'uniprot_tr_dir' => '',
'pipeline_comment' => '',

# database details for the eHive pipe database
'server1' => '',
'port1' => '',
'pipeline_dbname' => '', # this db will be created

'pipeline_db' => {
                    -dbname => $self->o('pipeline_dbname'),
                    -host   => $self->o('server1'),
                    -port   => $self->o('port1'),
                    -user   => $self->o('user_w'),
                    -pass   => $self->o('password'),
                    -driver => $self->o('driver'),
                 },
  };
}

sub pipeline_create_commands {
    my ($self) = @_;
    return [
      # inheriting database and hive tables' creation
	    @{$self->SUPER::pipeline_create_commands},
    ];
  }


## See diagram for pipeline structure
sub pipeline_analyses {
    my ($self) = @_;

    return [
      {
        -input_ids => [{}],
        -logic_name => 'import_species_data',
        -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
        -parameters => {
                          cmd => 'perl '.$self->o('import_species_script').
                                 ' -user '.$self->o('userstamp').
                                 ' -species '.$self->o('species').
                                 ' -release '.$self->o('release').
                                 ' -registry_host '.$self->o('registry_host').
                                 ' -registry_user '.$self->o('registry_user').
                                 ' -registry_pass '.$self->o('registry_pass').
                                 ' -registry_port '.$self->o('registry_port')
                       },
        -rc_name    => 'default',
        -flow_into => { 1 => ['get_release_mapping_history_id'] },
      },

      {
        -logic_name => 'get_release_mapping_history_id',
        -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
        -parameters => {
                          cmd => '' # REST API call
        },
        -rc_name => 'default',
        -flow_into => { 1 => ['wait_for_uniprot_mappings'] },
      },

      # this analysis will have to be set to DONE to resume the pipeline once UniProt
      # have loaded their mappings into the GIFTS database
      {
        -logic_name => 'wait_for_uniprot_mappings',
        -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        -parameters => {},
        -rc_name          => 'default',
        -wait_for => ['perfect_match_alignments'],
        -flow_into => { 1 => ['perfect_match_alignments'] },
      },

      {
        -logic_name => 'perfect_match_alignments',
        -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
        -parameters => {
                          cmd => 'perl '.$self->o('perfect_match_script').
                                 ' -output_dir '.$self->o('output_dir').
                                 ' -output_prefix '.$self->o('output_prefix').
                                 ' -registry_host '.$self->o('registry_host').
                                 ' -registry_user '.$self->o('registry_user').
                                 ' -registry_pass '.$self->o('registry_pass').
                                 ' -registry_port '.$self->o('registry_port').
                                 ' -user '.$self->o('userstamp').
                                 ' -species '.$self->o('species').
                                 ' -release '.$self->o('release').
                                 ' -release_mapping_history_id #release_mapping_history_id#'.
                                 ' -uniprot_sp_file '.$self->o('uniprot_sp_file').
                                 ' -uniprot_sp_isoform_file '.$self->o('uniprot_sp_isoform_file').
                                 ' -uniprot_tr_dir '.$self->o('uniprot_tr_dir').
                                 ' -pipeline_name '.$self->o('pipeline_name').
                                 ' -pipeline_comment '.$self->o('pipeline_comment_perfect_match')
                       },
        -rc_name    => 'default_10GB',
        -flow_into => { 1 => ['get_perfect_match_alignment_run_id'] },
      },

      {
        -logic_name => 'get_perfect_match_alignment_run_id',
        -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
        -parameters => {
                          cmd => '' # REST API call
        },
        -rc_name => 'default',
        -wait_for => ['perfect_match_alignments']
        -flow_into => { 1 => ['blast_cigar_alignments'] },
      },

      {
        -logic_name => 'blast_cigar_alignments',
        -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
        -parameters => {
                          cmd => 'perl '.$self->o('blast_cigar_script').
                                 ' -user '.$self->o('userstamp').
                                 ' -perfect_match_alignment_run_id #perfect_match_alignment_run_id#'.
                                 ' -registry_host '.$self->o('registry_host').
                                 ' -registry_user '.$self->o('registry_user').
                                 ' -registry_pass '.$self->o('registry_pass').
                                 ' -registry_port '.$self->o('registry_port').
                                 ' -pipeline_name '.$self->o('pipeline_name').
                                 ' -pipeline_comment '.$self->o('pipeline_comment_blast_cigar').
                                 ' -output_dir '.$self->o('output_dir')
                       },
        -rc_name    => 'default_10GB',
        -flow_into => { 1 => ['blast_cigar_alignments'] },
      }
    ];
  }

sub pipeline_wide_parameters {
    my ($self) = @_;

    return {
	    %{ $self->SUPER::pipeline_wide_parameters() },  # inherit other stuff from the base class
    };
  }

sub resource_classes {
    my $self = shift;
    return {
      'default' => { LSF => '-M1900 -R"select[mem>1900] rusage[mem=1900]"' },
      'default_10GB' => { LSF => '-M10000 -R"select[mem>10000] rusage[mem=10000]"' },
    }
  }

1;