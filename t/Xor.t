#!/usr/bin/perl

# Copyright 2008 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3, or (at your option) any later
# version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.


use strict;
use warnings;
use Gtk2::Ex::Xor;
use Test::More tests => 5;

ok ($Gtk2::Ex::Xor::VERSION >= 3);
ok (Gtk2::Ex::Xor->VERSION  >= 3);

SKIP: {
  require Gtk2;
  if (! Gtk2->init_check) { skip 'due to no DISPLAY available', 3; }

  my $toplevel = Gtk2::Window->new ('toplevel');

  my $label = Gtk2::Label->new;
  $toplevel->add ($label);
  $label->{'Gtk2_Ex_Xor_background'} = 'polkadot';
  is ($toplevel->Gtk2_Ex_Xor_background, 'polkadot',
      'Gtk2::Window containing label gets label background');

  $toplevel->{'Gtk2_Ex_Xor_background'} = 'purple';
  is ($toplevel->Gtk2_Ex_Xor_background, 'purple',
      'Gtk2::Window containing Label own overridden background');

  $toplevel->remove ($label);
  my $area = Gtk2::DrawingArea->new;
  $toplevel->add ($area);
  $area->{'Gtk2_Ex_Xor_background'} = 'pink';
  is ($toplevel->Gtk2_Ex_Xor_background, 'purple',
      'Gtk2::Window containing DrawingArea own overridden background');

  $toplevel->destroy;
}

exit 0;
