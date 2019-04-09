# SPDX-License-Identifier: LGPL-2.1 OR BSD-2-Clause
project('libbpf', 'c',
        version : '0.0.3',
        license : 'LGPL-2.1 OR BSD-2-Clause',
        default_options : [
                'prefix=/usr',
        ],
        meson_version : '>= 0.46',
        )

patchlevel = meson.project_version().split('.')[1]

libbpf_source_dir = './'

libbpf_sources = files(run_command('find',
        [
        '@0@/src'.format(libbpf_source_dir),
        '-type',
        'f',
        '-name',
        '*.[h|c]']).stdout().split())

libbpf_headers = files(
        join_paths(libbpf_source_dir, 'src/bpf.h'),
        join_paths(libbpf_source_dir, 'src/btf.h'),
        join_paths(libbpf_source_dir, 'src/libbpf.h'))

feature_rellocarray = run_command(join_paths(libbpf_source_dir, 'scripts/check-reallocarray.sh'))

libbpf_c_args = ['-g',
                '-O2',
                '-Werror',
                '-Wall',
]

if feature_rellocarray.stdout().strip() != ''
        libbpf_c_args += '-DCOMPAT_NEED_REALLOCARRAY'
endif

# bpf_includes are required to include bpf.h, btf.h, libbpf.h
bpf_includes = include_directories(
        join_paths(libbpf_source_dir, 'src'))

libbpf_includes = include_directories(
        join_paths(libbpf_source_dir, 'include'),
        join_paths(libbpf_source_dir, 'include/uapi'))

libelf = dependency('libelf')
libelf = dependency('libelf', required: false)
if not libelf.found()
        libelf = cc.find_library('elf', required: true)
endif

deps = [libelf]

libbpf_static = static_library(
        'bpf',
        libbpf_sources,
        c_args : libbpf_c_args,
        dependencies : deps,
        include_directories : libbpf_includes,
        install : true)

libbpf_static_dep = declare_dependency(link_with : libbpf_static)

libbpf_map_source_path = join_paths(libbpf_source_dir, 'src/libbpf.map')
libbpf_map_abs_path = join_paths(meson.current_source_dir(), libbpf_map_source_path)

libbpf_c_args += ['-fPIC', '-fvisibility=hidden']

libbpf_link_args = ['-Wl,--version-script=@0@'.format(libbpf_map_abs_path)]

libbpf_shared = shared_library(
        'bpf',
        libbpf_sources,
        c_args : libbpf_c_args,
        dependencies : deps,
        include_directories : libbpf_includes,
        install : true,
        link_args : libbpf_link_args,
        link_depends : libbpf_map_source_path,
        soversion : patchlevel,
        version : meson.project_version())

libbpf_shared_dep = declare_dependency(link_with : libbpf_shared)

install_headers(libbpf_headers, subdir : 'bpf')

pkg = import('pkgconfig')
pkg.generate(
        name: meson.project_name(),
        version: meson.project_version(),
        libraries: libbpf_shared,
        requires_private: ['libelf'],
        description: '''BPF library''')
