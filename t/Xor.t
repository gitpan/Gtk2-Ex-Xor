#!/usr/bin/perl

# Copyright 2008, 2009 Kevin Ryde

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
use Test::More tests => 7;

my $want_version = 6;
cmp_ok ($Gtk2::Ex::Xor::VERSION, '>=', $want_version,
        'VERSION variable');
cmp_ok (Gtk2::Ex::Xor->VERSION,  '>=', $want_version,
        'VERSION class method');
{ ok (eval { Gtk2::Ex::Xor->VERSION($want_version); 1 },
      "VERSION class check $want_version");
  my $check_version = $want_version + 1000;
  ok (! eval { Gtk2::Ex::Xor->VERSION($check_version); 1 },
      "VERSION class check $check_version");
}

require Gtk2;
diag ("Perl-Gtk2 version ",Gtk2->VERSION);
diag ("Perl-Glib version ",Glib->VERSION);
diag ("Compiled against Glib version ",
      Glib::MAJOR_VERSION(), ".",
      Glib::MINOR_VERSION(), ".",
      Glib::MICRO_VERSION(), ".");
diag ("Running on       Glib version ",
      Glib::major_version(), ".",
      Glib::minor_version(), ".",
      Glib::micro_version(), ".");
diag ("Compiled against Gtk version ",
      Gtk2::MAJOR_VERSION(), ".",
      Gtk2::MINOR_VERSION(), ".",
      Gtk2::MICRO_VERSION(), ".");
diag ("Running on       Gtk version ",
      Gtk2::major_version(), ".",
      Gtk2::minor_version(), ".",
      Gtk2::micro_version(), ".");

#-----------------------------------------------------------------------------

SKIP: {
  Gtk2->disable_setlocale;  # leave LC_NUMERIC alone for version nums
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
