# Workflow de mise a jour: commit des modifs sur le SVN infra, mise a jour de
# cette macro %{revision} pour pointer sur le nO de rev a packager
%define revision 6606
%define repository svn://svn-infra/Infra/INF/src/purge-any/
Name:           purge-any
Summary:        Script de purge multiplateforme pour Idgroup
Group:		Applications/File
Version:        1.014
Release:        2%{?dist}
License:        GPLv2+
Vendor:         Idgroup
Packager:       Thomas Equeter <thomas@users.noreply.github.com>
BuildArch:      noarch
BuildRoot:      %{_tmppath}/%{name}-root-%(%{__id_u} -n)
Source:         %{repository}

%if "%{?dist}" == ".el7"
# Untested, trying the same as EL6
%define perldeps perl >= 5.8.8, perl-Log-Log4perl >= 1.26, perl-YAML-LibYAML >= 0.32, perl-DateTime >= 0.53, perl-IO-Compress-Zlib >= 2.001
%else
%if "%{?dist}" == ".el6"
# NB: RHEL6's DateTime RPM also provides perl-DateTime-Locale >= 0.45 and perl-DateTime-TimeZone >= 1.01
%define perldeps perl >= 5.8.8, perl-Log-Log4perl >= 1.26, perl-YAML-LibYAML >= 0.32, perl-DateTime >= 0.53, perl-IO-Compress-Zlib >= 2.001
%else
%if "%{?dist}" == ".el5"
# RHEL5 has no perl-IO-Compress-Zlib installable (even through ext repos)
# and the DateTime are from DAG, so we need the subpackages
%define perldeps perl >= 5.8.8, perl-Log-Log4perl >= 1.26, perl-YAML-LibYAML >= 0.32, perl-DateTime >= 0.53, perl-DateTime-Locale, perl-DateTime-TimeZone
%else
# Tentatively go for the full list, untested.
%define perldeps perl >= 5.8.8, perl-Log-Log4perl >= 1.26, perl-YAML-LibYAML >= 0.32, perl-DateTime >= 0.53, perl-DateTime-Locale, perl-DateTime-TimeZone, perl-IO-Compress-Zlib >= 2.001
%endif
%endif
%endif

BuildRequires:  subversion, %{perldeps}, perl-Pod-Simple
Requires:	%{perldeps}

%description 
Script de purge de fichiers multiplateforme.


%define testdir %{_datadir}/purge-any-%{version}

%files
%attr(0755, root, root)               %{_bindir}/purge-any
                                      %{testdir}
%doc                                  _docs_staging/*

# Empeche la generation de Provides depuis les sources
# (nous ne fournissons pas module, et il ne faut pas prendre en compte la lib
# interne PurgeTestCommons).
%define __perl_provides %{nil} 

%prep
export LANG=en_US.UTF-8
svn export --quiet --force -r %{revision} %{repository} .

%build
export LANG=en_US.UTF-8
chmod 755 pod2cpanhtml purge-any.pl
./pod2cpanhtml <purge-any.pl >purge-any.html
prove t

%install
export LANG=en_US.UTF-8
rm -rf "%{buildroot}" _docs_staging
mkdir -p "%{buildroot}%{_bindir}" "%{buildroot}%{testdir}"
cp purge-any.pl "%{buildroot}%{_bindir}/purge-any"
cp -a t "%{buildroot}%{testdir}/"
ln -s %{_bindir}/purge-any "%{buildroot}%{testdir}/purge-any.pl"
mkdir -p _docs_staging
cp purge-any.conf _docs_staging/purge-any.conf.example
cp CHANGELOG.txt README.txt purge-any.html _docs_staging/

%clean
rm -rf "%{buildroot}"

%changelog
* Wed Apr 15 2015 Thomas Equeter <thomas@users.noreply.github.com> 1.014-2
- Made the IO::Compress::Gzip dependency optional on GNU platforms, for an
  easier installation method on RHEL5.
- Improved error reporting on opendir
- Avoid an out of memory condition on large directories
- Detect TAB characters in the configuration file and treat them as fatal
  errors.
- Updated documentation for installation on RHEL5 & RHEL6
* Mon Apr 13 2015 Thomas Equeter <thomas@users.noreply.github.com> 1.013-1
- First RPM packaging
