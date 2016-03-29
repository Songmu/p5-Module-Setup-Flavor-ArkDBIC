package Module::Setup::Flavor::Ark;
use strict;
use warnings;

use base 'Module::Setup::Flavor';

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
file: cpanfile
template: |
  requires 'Ark';
  requires 'DateTime';
  requires 'DBIx::Class';
  requires 'FindBin::libs';
  requires 'SQL::Translator';
  requires 'String::CamelCase';
  requires 'Text::MicroTemplate::Extended';
  requires 'Text::MicroTemplate::DataSection';
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
file: lib/____var-module_path-var____.pm
template: |
  package [% module %];
  use Ark;

  use_model '[% module %]::Models';
  our $VERSION = '0.01';

  __PACKAGE__->meta->make_immutable;

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

  __PACKAGE__->meta->make_immutable;
---
file: script/dev/skeleton.pl
chmod: 0700
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

  $name = camelize $name if (grep {$type eq $_} @{[qw/controller schema/]});
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

  __PACKAGE__->meta->make_immutable;

  @@ schema.mt
  package [% module %]::Schema::Result::<?= $name ?>;

  use strict;
  use warnings;
  use utf8;
  use parent qw/[% module %]::Schema::ResultBase/;

  use [% module %]::Schema::Types;
  use [% module %]::Models;

  __PACKAGE__->table('<?= $decamelized ?>');
  __PACKAGE__->add_columns(
      id => {
          data_type   => 'INTEGER',
          is_nullable => 0,
          is_auto_increment => 1,
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
---
dir: lib/____var-module_path-var____/Controller
---
dir: lib/____var-module_path-var____/Schema/Result
---
dir: lib/____var-module_path-var____/Schema/ResultSet
---
dir: lib/____var-module_path-var____/Schema/View
---
dir: tmp/
---
dir: root/
