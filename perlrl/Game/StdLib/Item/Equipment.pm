package Game::StdLib::Item::Equipment;

use strict;
use warnings;
use Util;

use base "Game::StdLib::Item";
__PACKAGE__->announce("Equipment");

# STAB US IN A RETINA
sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);
  $self->_construct(\%opts => "Power", "Accuracy", "Mod", "OOD");
  $self->{OOD} ||= 0;
  $self->{Mod} ||= [ random(0, $self->{OOD}), random(0, $self->{OOD}) ];
  
  return $self;
}

# Describe ourselves. You know, for personal ads. +5 equipment of.. well, you know. ;)
sub name {
  my ($self, $style) = @_;
  return $self->Name unless $style;

  my $name;

  # +5? flaaaaaaaming?
  if ($self->{Mod}[0] == $self->{Mod}[1]) {
    $name .= sprintf("%+d ", $self->{Mod}[0]) unless $self->{Mod}[0] == 0;
  } else {
    $name .= sprintf("%+d,%+d ", @{ $self->{Mod} });
  }

  $name .= $self->Name;

  if ($style eq "general") {
    # So if we have a mod, 'a' because "PLUS 5" is a consonant sound
    return $name =~ m/^(a|e|i|o|u)/ ? "an $name" : "a $name";
  } elsif ($style eq "specific") {
    return "the $name";
  } elsif ($style eq "inv") {
    $name = "$self->{Index} - $name";
    if ($self->{On}) {
      $name .= $self->{On} eq "Hand" ? " (wielded)" : " (worn)";
    }
    if (my $affinity = $self->Affinity) {
      $name = "<green>$name" if Player and Player->Affinity eq $affinity;
    }
    return $name;
  } elsif ($style eq "plain") {
    return $name; # Almost name(), but we want modifiers
  }
}

# TODO: technically armour/weapon only but eh?

# Is it over 9000?
sub power {
  my $self = shift;
  my $base = $self->Power * CFG->{Scale}{Power};
  return random($base - CFG->{Scale}{ItemDeviance}, $base + CFG->{Scale}{ItemDeviance}) + $self->{Mod}[0];
}

sub accuracy {
  my $self = shift;
  return $self->Accuracy * CFG->{Scale}{Accuracy} + $self->{Mod}[1];
}

sub describe {
  my $self = shift;
  my @lines;
  push @lines, $self->name("inv");
  push @lines, $self->Descr;
  push @lines, "$_: " . $self->$_ for qw(Affinity Power Accuracy);
  my $chance = 100 - CFG->{DunGen}{RareItem} * abs $self->ood(Player->{Map}{Depth});
  push @lines, "Rank: " . $self->Rank . " ($chance% here)";
  return @lines;
}

package Game::StdLib::Item::Equipment::Weapon;

our @ISA = ("Game::StdLib::Item::Equipment");
__PACKAGE__->announce("Weapon");

# We don't need extra constructor magic!

__PACKAGE__->classdat(
  Category => "Weapons",
  Fits     => ["Weapon"],
  Symbol   => ")",
  Attack   => {}
);

package Game::StdLib::Item::Equipment::Weapon::Ranged;

our @ISA = ("Game::StdLib::Item::Equipment::Weapon");
__PACKAGE__->announce("RangedWeapon");

__PACKAGE__->classdat(
  Projectile => ["+", "Red"],
  Ammo       => undef
);

package Game::StdLib::Item::Equipment::Mask;

our @ISA = ("Game::StdLib::Item::Equipment");
__PACKAGE__->announce("Mask");

__PACKAGE__->classdat(
  Category => "Masks",
  Fits     => ["Mask"],
  Symbol   => "]"
);

42;
