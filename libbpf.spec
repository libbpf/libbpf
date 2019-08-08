Name:           libbpf
Version:        0.0.4
Release:        1%{?dist}
Summary:        Libbpf library
Group:          Development/System
Packager:       Julia Kartseva <hex@fb.com>

License:        GPL-2.1 OR BSD-2-Clause
URL:            https://github.com/libbpf/libbpf
Source:         libbpf-%{version}-%{release}.tar.gz
BuildRequires:  elfutils-libelf-devel elfutils-devel

%description
A mirror of bpf-next linux tree bpf-next/tools/lib/bpf directory plus its
  supporting header files. The version of the package reflects the version of
  ABI.

%package devel
Summary: Development files for %{name}
Requires: %{name} = %{version}-%{release}

%description devel
The %{name}-devel package contains libraries header files for
developing applications that use %{name}

%prep
%autosetup

%build
%make_build -C ./src DESTDIR=%{buildroot} OBJDIR=%{_builddir}

%install
%make_install -C ./src DESTDIR=%{buildroot} OBJDIR=%{_builddir}

%clean
rm -rf "%{buildroot}"

%files
%attr(0755,-,-) %{_libdir}/libbpf.so.%{version}
%{_libdir}/libbpf.so.0
%{_libdir}/libbpf.so

%files devel
%attr(0644,-,-) %{_includedir}/bpf/bpf.h
%attr(0644,-,-) %{_includedir}/bpf/btf.h
%attr(0644,-,-) %{_includedir}/bpf/libbpf.h
%attr(0644,_,_) %{_includedir}/bpf/libbpf_util.h
%attr(0644,_,_) %{_includedir}/bpf/xsk.h
%attr(0644,-,-) %{_libdir}/libbpf.a
%attr(0644,-,-) %{_libdir}/pkgconfig/libbpf.pc

%changelog
* Thu Aug 8 2019 Julia Kartseva <hex@fb.com> - 0.0.4-1%{?dist}
- Initial release
