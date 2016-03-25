#############
# Container #
#############

package Roguelike::Container;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

sub new {
  my $self = bless {
    List => [],
    Index => {},
    Category => {},
    Ordered => 0
  }, shift;
  my $ordered = shift;
  my $owner = shift;
  $self->{Ordered} = $ordered;
  $self->{Owner} = $owner;
  return $self;
}

sub get {
  my ($self, $i) = @_;
  if ($self->{Ordered}) {
    return $self->{List}[ $self->{Index}{$i} ] if defined $self->{Index}{$i};
  } else {
    return $self->{List}[$i];
  }
}

sub add {
  my ($self, $obj) = @_;
  # Determine if we should try to combine the new object with an existing one
  # by combining quantities or create a new item.
  my $group = $Game->{Config}{Category}{ $obj->g("Category") }{Group};
  if ($group != 0 and keys %{ $self->{Category}{ $obj->g("Category") } }) {
    foreach my $item (keys %{ $self->{Category}{ $obj->g("Category") } }) {
      $item = $self->get($item);
      my $err = 0;
      unless ($group == 1) {
        foreach my $stat (@$group) {
          $err = 1, last unless $obj->g($stat) eq $item->g($stat);
        }
      }
      next if $err;
      $item->{Qty} = $item->g("Qty") + $obj->g("Qty");
      # Pull a little reference magic here so things still referencing $obj
      # will now get $item.
      $obj = $item;
      return $item;
    }
  }
  push @{ $self->{List} }, $obj;
  $obj->{Index} = $#{ $self->{List} };
  if ($self->{Ordered}) {
    my $letter;
    foreach ("a" .. "z", "A" .. "Z") {
      $letter = $_, last unless defined $self->{Index}{$_};
    }
    $self->{Index}{$letter} = $obj->g("Index");
    $obj->{Index} = $letter;
  }
  $self->{Category}{ $obj->g("Category") }{ $obj->g("Index") } = 1;
  $obj->{Area} = $self;
  return $obj;
}

sub del {
  my ($self, $i) = @_;
  $i = $self->{Index}{$i} if defined $self->{Index}{$i};
  my $obj = $self->{List}[$i];
  $obj->{Area} = undef;
  # Delete the item's possible entry in the index.
  if ($self->{Ordered}) {
    delete $self->{Index}{ $obj->g("Index") };
  }
  # Remove its entry in the category list.
  delete $self->{Category}{ $obj->g("Category") }{ $obj->g("Index") };
  # Remove it out from the stack.
  splice(@{ $self->{List} }, $i, 1);
  # Update the items' index.
  foreach ($i .. $#{ $self->{List} }) {
    my $item = $self->{List}[$_];
    if ($self->{Ordered}) {
      $self->{Index}{ $item->g("Index") }--;
    } else {
      $item->{Index}--;
    }
  }
  return $obj;
}

sub all {
  my $self = shift;
  return @{ $self->{List} };
}

42;
