#!/usr/bin/perl

# Copyright 2007, 2008, 2009 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 3, or (at your option) any
# later version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.

use 5.008;
use strict;
use warnings;
use ExtUtils::MakeMaker;
use lib 'inc';
use MyMakeMakerExtras;

WriteMakefile
  (NAME         => 'Gtk2-Ex-Xor',
   ABSTRACT     => 'Helpers for Gtk2 widgets.',
   VERSION_FROM => 'lib/Gtk2/Ex/Xor.pm',
   AUTHOR       => 'Kevin Ryde <user42@zip.com.au>',
   LICENSE      => 'gpl',
   SIGN         => 1,

   PREREQ_PM    => {
                    # version 1.200 for Gtk2::GC auto-release and various
                    'Gtk2' => '1.200',

                    # my Glib-Ex-ObjectBits
                    'Glib::Ex::SignalIds' => 0,

                    # my Gtk2-Ex-WidgetBits
                    'Gtk2::Ex::WidgetBits' => 0,
                    'Gtk2::Ex::KeySnooper' => 0,
                    'Gtk2::Ex::SyncCall' => 0,

                    # optional for Lasso but mandatory for CrossHair
                    # version 5 for weakening fixes
                    'Gtk2::Ex::WidgetCursor' => 5,
                   },
   clean        => { FILES => "CrossHair.html Lasso.html Xor.html" },

   EXTRA_META => MyMakeMakerExtras::strip_comments(<<'HERE'),
optional_features:
    maximum_tests:
        description: Have "make test" do as much as possible.
        requires:
            Parse::CPAN::Meta: 0
            Test::Pod: 1.00
            Test::NoWarnings: 0
            Test::DistManifest: 0
            # Test::YAML::Meta: 0
            YAML: 0
            YAML::Syck: 0
            YAML::Tiny: 0
            YAML::XS: 0
no_index:
    package:
        # use of "package Gtk2::Bin" adding a private method
        - Gtk2::Bin
    directory:
        - devel
        - inc
        - t
resources:
    homepage: http://user42.tuxfamily.org/gtk2-ex-xor/index.html
    license: http://www.gnu.org/licenses/gpl.html
HERE
  );

#------------------------------------------------------------------------------
package MY;
sub postamble {
  my ($makemaker) = @_;
  return MyMakeMakerExtras::postamble($makemaker);
}
