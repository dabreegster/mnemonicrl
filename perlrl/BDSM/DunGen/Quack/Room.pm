package BDSM::DunGen::Room;

use strict;
use warnings;
use Util;

use BDSM::Toy::Conveyor;

sub generate {
  my ($class, $height, $width) = @_;

  # We need room for wall-sprites to pull completely out though
  my $map = BDSM::Map->new(3 * $height, 3 * $width, " ");
  $map->border;

  # Draw room
  $map->fill([$height, $width], [$height * 2, $width * 2], ".");
  $map->border;

  # Make some traps along each wall...
  my @x = shuffle($width + 1 .. ($width * 2) - 1);
  my @y = shuffle($height + 1 .. ($height * 2) - 1);

  # TODO buggyness a bit
  # TODO not sure why +1 sometimes. offsets alll crazy
  GAME->make("RmWall",
    Dir    => "s",
    Map    => $map,
    Color  => "red",
    At     => [0, shift @x],
    Width  => 1,
    Height => $height
  ) for 1 .. $width / 10;

  GAME->make("RmWall",
    Dir    => "n",
    Map    => $map,
    Color  => "red",
    At     => [($height * 2) + 1, shift @x],
    Width  => 1,
    Height => $height
  ) for 1 .. $width / 10;

  GAME->make("RmWall",
    Dir    => "e",
    Map    => $map,
    Color  => "red",
    At     => [shift @y, 0],
    Width  => $width,
    Height => 1
  ) for 1 .. $height / 3;

  GAME->make("RmWall",
    Dir    => "w",
    Map    => $map,
    Color  => "red",
    At     => [shift @y, $width * 2],
    Width  => $width,
    Height => 1
  ) for 1 .. $height / 3;

  $map->{_Data}{$_} = 1 for qw(empty superlight nostairs);
  return $map;
}

package BDSM::Agent::Sprite::WallMonster;

use strict;
use warnings;
use Util;

use base "BDSM::Agent::Sprite";
__PACKAGE__->announce("RmWall");

use BDSM::Vector;

sub new {
  my ($class, %opts) = @_;
  my $shape;
  my $w = delete $opts{Width};
  my $h = delete $opts{Height};
  my $sym = {
    n => "^",
    s => "v",
    e => ">",
    w => "<"
  }->{ $opts{Dir} };
  if ($h > 1) {
    $shape = "$sym\n" x $h;
  } else {
    $shape = "$sym" x $w;
  }

  # Clear out the map
  my ($y, $x) = @{ $opts{At} };
  if ($opts{Dir} eq "e") {
    $opts{Map}->mod($y, $x + $w, ".");
  } elsif ($opts{Dir} eq "w" or $opts{Dir} eq "n") {
    $opts{Map}->mod($y, $x, ".");
  } elsif ($opts{Dir} eq "s") {
    $opts{Map}->mod($y + $h, $x, ".");
  }

  my $self = $class->SUPER::new(%opts, Shapes => { default => $shape });
  die "Wall $opts{Dir} couldn't be placed\n" if $self->void;
  $self->_construct(\%opts => "Dir");
  $self->{Sliding} = 0;

  my $start = sub {
    return unless GAME->fullsim;
    return if $self->{Sliding};
    $self->{Sliding} = 1;
    GAME->schedule(
      -do => [$self, "slide"],
      -id => "wallmv_$self->{ID}",
      -tags => ["wallmonster"]
    );
  };
  my @path;
  if ($self->{Dir} eq "n") {
    push @path, [$_, $self->{X}] for $self->{Y} - $h .. $self->{Y} - 1;
  } elsif ($self->{Dir} eq "s") {
    push @path, [$_, $self->{X}] for $self->{Y} + $h + 1 .. $self->{Y} + ($h * 2);
  } elsif ($self->{Dir} eq "w") {
    push @path, [$self->{Y}, $_] for $self->{X} - $w + 1 .. $self->{X} - 1;
  } elsif ($self->{Dir} eq "e") {
    push @path, [$self->{Y}, $_] for $self->{X} + $w + 1 .. $self->{X} + ($w * 2) - 1;
  }
  $self->{Map}->tile(@$_)->{OnEnter} = $start foreach @path;

  return $self;
}

sub BEFORE_slide {
  my ($wall, $heap) = actargs @_;
  my $info = {};
  my $dir = $wall->{Dir} // die "wall doesnt know its dir\n";
  unless ($wall->$dir(-heap => $info)) {
    my $what = $info->{Collided};
    if ($what and $what->type ne "RmWall") {
      msg see => "hit " . $info->{Collided}->id;
    }
    # Turn back
    $wall->{Dir} = opposite_dir($dir);
  }
  $heap->{Return} = 0.05;
  return STOP;
}

sub pushedby { 0 }  # Oh hell no

42;
