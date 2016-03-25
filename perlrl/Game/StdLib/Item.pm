package Game::StdLib::Item;

use strict;
use warnings;
use Util;

use POSIX ("ceil");

use base "Game::Object";
__PACKAGE__->announce("Item");

__PACKAGE__->classdat(
  GroupBy  => [],   # Don't group stuff by default.
  Affinity => "ANY",
  Verb     => ""
);

# PICK ME PICK ME PICK ME UUUUP
sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  $self->_construct(\%opts => "Name", "Symbol", "Color");
  $self->{Qty} = $opts{Qty} || 1;

  # We're either on a map or in someone's inventory
  if (my $map = $opts{On}) {
    my ($y, $x);
    # We going somewhere in particular or just anywhere?
    if ($opts{At}) {
      ($y, $x) = @{ $opts{At} };
    } else {
      ($y, $x) = $map->spawnpt;
    }
    $map->inv($y, $x, "add", $self);
  } elsif (my $owner = delete $opts{BelongsTo}) {
    $owner->{Inv}->add($self);
  }

  return $self;
}

# Pack ourselves in giftwrapping
sub serialize {
  my $self = shift;

  # Do a shallow copy of the sprite's data.
  my $send = { %$self };
  delete $send->{Owner};  # We'll know this.

  return bless($send, ref $self);
}

sub unserialize {
  return unless @_ == 4;  # Who cares unless we're on a map
  my ($self, $map, $y, $x) = @_;

  $map->inv($y, $x, "_client_add", $self);  # TODO lol
}

sub display {
  my $self = shift;
  my $sym;
  my $color = $self->Color;
  unless ($sym = $self->Symbol) {
    $sym = "?";
    $color = "white/Red";
    debug "dunno what we (item) look like!";
  }
  return ($sym, $color);
}

sub describe {
  my $self = shift;
  my @lines;
  push @lines, $self->name("inv");
  push @lines, $self->Descr;
  return @lines;
}

# For generics
sub name {
  my ($self, $style) = @_;
  my $name = $self->Name;
  return $self->Name if !$style or $style eq "plain";
    
  if ($style eq "general") {
    return $name =~ m/^(a|e|i|o|u)/ ? "an $name" : "a $name";
  } elsif ($style eq "specific") {
    return "the $name";
  } elsif ($style eq "inv") {
    return "$self->{Index} - $name";
  }
}

sub ood {
  my ($self, $z) = @_;
  return 0 unless $z =~ m/^\d+$/;
  return ceil($z / CFG->{Scale}{DLvlRatio}) - $self->Rank;
}

42;
