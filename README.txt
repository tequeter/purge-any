purge-any
=========

purge-any is a schedulable, cross-platform tool for purging files with a single,
structured configuration. This configuration contains several profiles,
one per host, and can therefore be replicated safely accross all servers.


Documentation
=============

The documentation is included at the bottom of purge-any.pl in POD format. It
can be accessed in the following ways:

- Online (text mode)

  purge-any.pl --man
  purge-any.exe --man

- Offline HTML

  browse to purge-any.html
  (generate this file with: ./pod2cpanhtml <purge-any.pl >purge-any.html)


Tests
=====

By deleting files on production servers, purge-any is a critical piece of
software. As such, it must be as free of bugs as possible.

There is a test-suite provided under the "t" directory (as is the custom for
Perl applications). You can run it at any time using the "prove" utility that
comes with Perl:

  prove t


Source control
==============

purge-any's history is on svn://svn-infra/Infra/INF/src/purge-any/ .


-Thomas Equeter, 2010-07-13.
