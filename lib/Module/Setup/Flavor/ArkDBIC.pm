package Module::Setup::Flavor::ArkDBIC;
use strict;
use warnings;

use base 'Module::Setup::Flavor::SelectVC';

sub loader {
    my $self = shift;
    $self->import_template('Module::Setup::Flavor::Default');
}

1;

=head1 NAME

Module::Setup::Flavor::ArkDBIC - Ark flavor

=head1 SYNOPSIS

  use Module::Setup::Flavor::ArkDBIC;

=cut

__DATA__

---
file: Makefile.PL
template: |
  use inc::Module::Install;

  name '[% module %]';
  all_from 'lib/[% module %].pm';

  requires 'Path::AttrRouter';
  requires 'Ark';

  requires 'Text::MicroTemplate::Extended';
  requires 'DateTime';
  requires 'FindBin::libs';
  requires 'DBIx::Class';
  requires 'SQL::Translator';
  requires 'DBD::mysql';
  requires 'DateTime::Format::MySQL';
  requires 'Module::Find';

  requires 'IO::Prompt';

  requires 'Text::MicroTemplate::DataSection';
  requires 'String::CamelCase';

  tests 't/*.t';
  author_tests 'xt';

  auto_set_repository;
  auto_include;

  WriteAll;
---
file: prod.psgi
template: |
  use lib 'lib';

  use Plack::Builder;
  use [% module %];
  use [% module %]::Models;

  my $app = [% module %]->new;
  $app->setup;

  # preload models
  my $models = [% module %]::Models->instance;
  $models->load_all;

  my $app = [% module %]->new;
  builder {
      $app->handler;
  };
---
file: dev.psgi
template: |
  use Plack::Builder;
  use Plack::Middleware::Static;
  use lib 'lib';

  use [% module %];

  my $app = [% module %]->new;
  $app->setup;

  builder {
      enable 'Plack::Middleware::Static',
          path => qr{^/(js/|css/|swf/|images?/|imgs?/|static/|[^/]+\.[^/]+$)},
          root => $app->path_to('root')->stringify;
      $app->handler;
  };
---
file: config.pl
template: |
  +{
      default_view    => 'MT',
  }
---
file: config_local.pl
template: |
  +{}
---
file: script/dev/upgrade_database.pl
template: |
  #!/usr/bin/env perl

  use strict;
  use warnings;

  use FindBin::libs;
  use Path::Class 'file';

  use Getopt::Long;
  use IO::Prompt qw/prompt/;

  my ($help, $dry_run, $test_db, $drop_table);
  GetOptions(
      'h|help'      => \$help,
      'd|dry-run'   => \$dry_run,
      'test-db'     => \$test_db,
      'drop-table'  => \$drop_table,
  ) or usage();
  exit usage() if $help;

  use SQL::Translator;
  use SQL::Translator::Diff;

  #local $ENV{ DBIC_TRACE } = 1;

  use [% module %]::Models qw/M/;

  if ( $test_db ) {
      require [% module %]::Test;
      [% module %]::Test->import;
  }
  my $schema = M('Schema');

  my $current_version = $schema->get_db_version;
  my $schema_version  = $schema->schema_version;
  my $dir             = $schema->upgrade_directory;

  print "current_version: $current_version\n";
  print "schema_version:  $schema_version\n";
  print "dir:             $dir\n";

  my $sqltargs = {
      add_drop_table          => 1,
      ignore_constraint_names => 1,
      ignore_index_names      => 1,
  };

  sub parse_sql {
      my ($file, $type) = @_;

      my $t = SQL::Translator->new($sqltargs);

      $t->parser($type)
          or die $t->error;

      my $out = $t->translate("$file")
          or die $t->error;

      my $schema = $t->schema;

      $schema->name( $file->basename )
          unless ( $schema->name );

      $schema;
  }

  no warnings 'redefine', 'once';
  my $upgrade_file;
  local *[% module %]::Schema::create_upgrade_path = sub {
      $upgrade_file = $_[1]->{upgrade_file};

      my $current_version = $schema->get_db_version;
      my $schema_version  = $schema->schema_version;
      my $database        = $schema->storage->sqlt_type;
      my $dir             = $schema->upgrade_directory;

      my $prev_file = $schema->ddl_filename($database, $current_version, $dir);
      my $next_file = $schema->ddl_filename($database, $schema_version, $dir);

      my $current_schema = eval { parse_sql file($prev_file), $database } or die $@;
      my $next_schema    = eval { parse_sql file($next_file), $database } or die $@;

      my $diff = SQL::Translator::Diff::schema_diff(
          $current_schema, $database,
          $next_schema, $database,
          $sqltargs,
      );

      if ($upgrade_file) {
          my $fh = file($upgrade_file)->openw or die $!;
          print $fh $diff;
          $fh->close;
      }
      else {
          print $diff;
      }
  };

  if ($dry_run) {
      $schema->create_upgrade_path;
      exit;
  }

  if ($drop_table) {
      exit unless prompt('drop table ok?[yn] ', '-y');
      $schema->deploy({add_drop_table => 1 });
      $schema->_set_db_version({version => $schema_version});
  }
  elsif (my $version = $schema->get_db_version) {
      $schema->upgrade;
      unlink $upgrade_file if $upgrade_file;
  }
  else {
      $schema->deploy;
  }

  sub usage {
      warn "see code\n";
  }
---
file: script/dev/create_ddl.pl
template: |
  #!/usr/bin/env perl

  use strict;
  use warnings;
  use FindBin::libs;
  use Path::Class qw/file/;

  use [% module %]::Models qw/M/;
  use Getopt::Long;
  use Pod::Usage;

  =DESCRIPTION

  Schema/ 以下を見てSQLを吐き出すスクリプト

  =head1 SYNOPSIS

      script/create_ddl.pl -p 1 --replace-version

       Options:
         -help            brief help message
         preversion       create DDL for diff from $preversion to current_version (optional)
         replace-version  replace $VERSION in MyApp::Schema (optional)

  =cut

  my ($preversion, $help, $replace_version);
  GetOptions(
      'h|help'          => \$help,
      'p|preversion=i'  => \$preversion,
      'replace-version' => \$replace_version,
  ) or die pod2usage;
  pod2usage(1) if $help;

  my $schema = M('Schema');

  my $current_version = $schema->schema_version;
  my $next_version    = $current_version + 1;
  $preversion       ||= $current_version;

  warn "current  version: $current_version\n";
  warn "db       version: ".$schema->get_db_version ."\n";
  warn "ddl from version: ".$preversion ."\n";
  warn "      to version: ".$next_version ."\n";

  $schema->create_ddl_dir(
      [qw/MySQL/],
      $next_version,
      "$FindBin::Bin/../../sql/",
      $preversion,
      +{
          parser      => 'SQL::Translator::Parser::DBIx::Class',
          parser_args => {
              quote_field_names => 1,
          },
      }
  );

  if ( $replace_version ) {
      # replace version
      my $f = file( $INC{'[% module %]/Schema.pm'} );
      my $content = $f->slurp;
      $content =~ s/(\$VERSION\s*=\s*(['"]?))(.+?)\2/$1$next_version$2/
          or die "Failed to replace version.";

      my $fh = $f->openw or die $!;
      print $fh $content;
      $fh->close;
  }
---
file: lib/____var-module_path-var____.pm
template: |
  package [% module %];
  use Ark;

  use_model '[% module %]::Models';
  our $VERSION = '0.01';

  config 'View::MT' => {
      use_cache => 1,

      macro => {
          stash => sub {
              __PACKAGE__->context->stash;
          },
      },
  };

  config 'Plugin::Session::Store::Model' => {
      model => 'session',
  };

  config 'Plugin::PageCache' => {
      model => 'cache',
  };

  config 'Plugin::Session' => {
      expires => '+30d',
  };

  1;
  __END__

  =head1 NAME

  [% module %] -

  =head1 SYNOPSIS

  use [% module %];

  =head1 DESCRIPTION

  [% module %] is

  =head1 AUTHOR

  [% config.author %] E<lt>[% config.email %]E<gt>

  =head1 SEE ALSO

  =head1 LICENSE

  This library is free software; you can redistribute it and/or modify
  it under the same terms as Perl itself.

  =cut
---
file: lib/____var-module_path-var____/Models.pm
template: |
  package [% module %]::Models;
  use strict;
  use warnings;
  use Ark::Models '-base';

  use Module::Find;

  register Schema => sub {
      my $self = shift;

      my $conf = $self->get('conf')->{database}
          or die 'require database config';

      $self->ensure_class_loaded('[% module %]::Schema');
      [% module %]::Schema->connect(@$conf);
  };

  my @modules = Module::Find::findallmod('[% module %]::Schema::Result');
  for my $module (@modules) {
      $module =~ s/[% module %]::Schema::Result:://;
      register "Schema::${module}" => sub {
          shift->get('Schema')->resultset($module);
      };
  }

  1;
---
file: lib/____var-module_path-var____/View/MT.pm
template: |
  package [% module %]::View::MT;
  use Ark 'View::MT';

  __PACKAGE__->meta->make_immutable;
---
file: lib/____var-module_path-var____/Schema.pm
template: |
  package [% module %]::Schema;
  use strict;
  use warnings;
  use parent 'DBIx::Class::Schema';
  use DateTime;

  our $VERSION = '0';

  __PACKAGE__->load_namespaces;

  __PACKAGE__->load_components('Schema::Versioned');
  __PACKAGE__->upgrade_directory('sql/');

  my $TZ = DateTime::TimeZone->new(name => 'Asia/Tokyo');
  sub TZ {$TZ}

  sub now {
      return DateTime->now(time_zone => $TZ);
  }

  1;
---
file: lib/____var-module_path-var____/Schema/ResultBase.pm
template: |
  package [% module %]::Schema::ResultBase;
  use strict;
  use warnings;
  use utf8;

  use DateTime;
  use parent 'DBIx::Class';

  __PACKAGE__->load_components(qw/InflateColumn::DateTime Core/);

  sub insert {
      my $self = shift;

      my $now = [% module %]::Schema->now;
      $self->created_at( $now ) if $self->can('created_at');
      $self->updated_at( $now ) if $self->can('updated_at');

      $self->next::method(@_);
  }

  sub update {
      my $self = shift;

      if ($self->can('updated_at')) {
          $self->updated_at( [% module %]::Schema->now );
      }

      $self->next::method(@_);
  }
  1;
---
file: lib/____var-module_path-var____/Controller.pm
template: |
  package [% module %]::Controller;
  use Ark 'Controller';
  use [% module %]::Models;

  # default 404 handler
  sub default :Path :Args {
      my ($self, $c) = @_;

      $c->res->status(404);
      $c->res->body('404 Not Found');
  }

  sub index :Path :Args(0) {
      my ($self, $c) = @_;
      $c->res->body('Ark Default Index');
  }

  sub end :Private {
      my ($self, $c) = @_;
      unless ($c->res->body or $c->res->status =~ /^3\d\d/) {
          $c->forward($c->view);
      }

  }

  1;
---
file: script/dev/skeleton.pl
template: |
  #!/usr/bin/env perl
  use strict;
  use warnings;
  use utf8;
  use FindBin::libs;
  use autodie;
  use [% module %]::Models;

  use Text::MicroTemplate::DataSectionEx;
  use String::CamelCase qw/camelize decamelize/;
  use Getopt::Long;
  use Pod::Usage;

  =head1 SYNOPSIS

      script/dev/skeleton.pl controller Controller::Name
      script/dev/skeleton.pl schema TableName
      script/dev/skeleton.pl view ViewName
      script/dev/skeleton.pl module Module::Name
      script/dev/skeleton.pl script batch/name

      Options:
         -help    brief help message

  =cut

  my $help;
  GetOptions('h|help' => \$help);
  pod2usage(1) if $help;

  my ($type, $name) = @ARGV;
  pod2usage(1) if !$name;

  $type = lc $type;

  my $config = +{
      controller  => {
          dirs  => [qw/lib [% module %] Controller/],
      },
      schema      => {
          dirs => [qw/lib [% module %] Schema Result/],
      },
      view        => {
          dirs => [qw/lib [% module %] View/],
      },
      module      => {
          dirs => [qw/lib/],
      },
      script  => {
          dirs  => [qw/script/],
          ext     => 'pl',
      },
  }->{$type};

  die "no definition for $type" unless $config;

  my @dirs = @{$config->{dirs}};
  my $ext = $config->{ext} || 'pm';

  $name = camelize $name if $type ~~ [qw/controller schema/];
  my $decamelized = decamelize($name);
  $decamelized =~ s!::!/!g;

  my $params = +{
      name        => $name,
      decamelized => $decamelized,
  };

  my $template = Text::MicroTemplate::DataSectionEx->new(
      template_args => $params,
  )->render_mt($type);

  my @file_dirs = split m!(?:(?:::)|/)!, $name;
  my $file = pop @file_dirs;
  $file .= ".$ext";
  push @dirs, @file_dirs;

  my $dir = models('home')->subdir(@dirs);
  $dir->mkpath unless -d $dir;
  $dir->file($file)->openw->write($template);

  __DATA__

  @@ controller.mt
  package [% module %]::Controller::<?= $name ?>;
  use Ark 'Controller';

  use [% module %]::Models;
  has '+namespace' => default => '<?= $decamelized ?>';

  sub auto :Private {
      1;
  }

  sub index :Path :Args(0) {
      my ($self, $c) = @_;
  }

  1;

  @@ schema.mt
  package [% module %]::Schema::Result::<?= $name ?>;

  use strict;
  use warnings;
  use utf8;
  use parent qw/[% module %]::Schema::ResultBase/;

  use [% module %]::Models;

  __PACKAGE__->table('<?= $decamelized ?>');
  __PACKAGE__->add_columns(
      id => {
          data_type   => 'INTEGER',
          is_nullable => 0,
          extra => {
              unsigned => 1,
          },
      },
  );

  sub sqlt_deploy_hook {
      my ($self, $sqlt_table) = @_;
      # $sqlt_table->add_index( fields => [qw//]);
      $self->next::method($sqlt_table);
  }

  __PACKAGE__->set_primary_key('id');

  1;

  @@ view.mt
  package [% module %]::View::<?= $name ?>;
  use Ark 'View::<?= $name ?>';

  __PACKAGE__->meta->make_immutable;

  @@ module.mt
  package <?= $name ?>;

  use strict;
  use warnings;
  use utf8;

  1;

  @@ script.mt
  #!/usr/bin/env perl
  use strict;
  use warnings;
  use FindBin::libs;

  use [% module %]::Models;
  use Getopt::Long;
  use Pod::Usage;

  local $| = 1;

  =head1 DESCRIPTION


  =head1 SYNOPSIS

      script/<?= $name ?>.pl

      Options:
         -help            brief help message

  =cut

  my $help;
  GetOptions(
      'h|help'          => \$help,
  ) or die pod2usage;
  pod2usage(1) if $help;

  1;

