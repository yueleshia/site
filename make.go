package main

import (
	"fmt"
	"log"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	_ "text/template"
)

var DEFAULT_DOMAIN = ""
var LANG_LIST = []string{"en", "zh", "jp"}


var STDERR_LOG = log.New(os.Stderr, "", 0)
type Env struct {
	root_dir string
	assets_dir string
	source_dir string
	templs_dir string
	output_dir string
	domain string
}

func main() {
	root_dir := Must(find_git_root())
	var domain, is_set = os.LookupEnv("SITE_DOMAIN")
	if !is_set {
		domain = DEFAULT_DOMAIN
	}
	env := Env {
		root_dir: root_dir,
		assets_dir: filepath.Join(root_dir, "assets"),
		source_dir: filepath.Join(root_dir, "source"),
		templs_dir: filepath.Join(root_dir, "templs"),
		output_dir: filepath.Join(root_dir, "public"),
		domain: domain,
	}

	for i, arg := range os.Args[1:] {
		if arg == "--" {
			continue
		}

		STDERR_LOG.Printf("== make.go %q ==", arg)

		switch (arg) {
		case "clean":
			STDERR_LOG.Printf("Remove directory %q", env.output_dir)
			os.RemoveAll(env.output_dir)

		case "local":
			new_env := env
			new_env.domain = root_dir
			build(new_env)

		case "host":
			build(env)

		case "server":
			if i != len(os.Args[1:]) - 1 {
				STDERR_LOG.Fatalf("Run 'server' last because it will block\n")
			}
			http.Handle("/", http.FileServer(http.Dir(env.output_dir)))
			http.Handle("/assets", http.FileServer(http.Dir(env.assets_dir)))

			port := 8080
			fmt.Printf("Server started at http://localhost:%d\n", port)
			if err := http.ListenAndServe(fmt.Sprintf(":%d", port), nil); err != nil {
				fmt.Printf("Error starting server: %s\n", err)
			}
		default:
			STDERR_LOG.Fatalf("Unsupported task: %s\n", arg)
		}
	}
	if 0 == len(os.Args[1:]) {
		build(env)
	}
}

func make_file(env Env, lang, template_relpath, src_relpath, out_relstem string) error {
	template_path := filepath.Join(env.templs_dir, template_relpath)
	src_path := filepath.Join(env.source_dir, src_relpath)
	out_stem := filepath.Join(env.output_dir, out_relstem)

	switch (filepath.Ext(template_relpath)) {
	case ".tmd":
		ext := ".html"
		STDERR_LOG.Printf("%q: %q -> %q", template_relpath, src_relpath, out_relstem + ext)

		env_vars := []string {
			"SITE_ROOT=" + env.root_dir,
			"SITE_SRC_PATH=" + src_path,
			"SITE_DOMAIN=" + env.domain,
			"SITE_ENDPOINT=" + out_relstem + ext,
			"SITE_LANGUAGE=" + lang,
		}
		//fmt.Println(env_vars)

		out_dir := filepath.Dir(out_stem)
		if err := os.MkdirAll(out_dir, 0770); err != nil {
			return fmt.Errorf("Could not create the directory: %q", out_dir)
		}

		if err := exec_write_stdout(env_vars, out_stem + ext, "tetra", "parse", template_path); err != nil {
			return err
		}

	//case ".scss":
	//	ext := ".css"
	//	STDERR_LOG.Printf("%q: %q -> %q", template_relpath, src_relpath, out_relstem + ext)
	//	retur
	case ".scss":
		ext := ".css"
		STDERR_LOG.Printf("%q: %q -> %q", template_relpath, src_relpath, out_relstem + ext)
		cmd := exec.Command("sassc", template_path, out_stem + ext)
		cmd.Stderr = os.Stderr
		if _, err := cmd.Output(); err != nil {
			return err
		}

	case ".html":
		ext := ".html"
		STDERR_LOG.Printf("%q: %q -> %q", template_relpath, src_relpath, out_relstem + ext)
		copy_file(out_stem + ext, src_path)

	case ".sh":
		// Skip
	default:
		return fmt.Errorf("Please add support for files with %q: %q", filepath.Ext(template_relpath), template_relpath)
	}
	return nil
}

func copy_file(dst_path, src_path string) error {
	src, err := os.Open(src_path)
	if err != nil {
		return fmt.Errorf("Cannot read from %q: %v", src_path, err)
	}

	dst, err := os.Create(dst_path)
	if err != nil {
		return fmt.Errorf("Cannot write to %q: %v", dst_path, err)
	}
	if _, err = io.Copy(dst, src); err != nil {
		return err
	}
	if err := dst.Sync(); err != nil {
		return err
	}
	if err := src.Close(); err != nil {
		return err
	}
	if err := dst.Close(); err != nil {
		return err
	}
	return nil
}

func exec_write_stdout(env_vars []string, out_path, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Env = append(cmd.Environ(), env_vars...)
	cmd.Stderr = os.Stderr
	out_bytes, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("Could not parse %q %s\n", name, args)
	}

	if err := os.WriteFile(out_path, out_bytes, 0644); err != nil {
		return fmt.Errorf("Failed to write to: %q\n  %v", out_path, err)
	}
	return nil
}




type Post struct{base string; stem string}

func build(env Env) {
	post_list := make([]string, 0, 1000)
	find_posts := func (path string, dir fs.DirEntry, err error) error {
		if dir.IsDir() {
			return nil
		}
		relpath, _ := strings.CutPrefix(path, env.source_dir)
		if relpath[0] == os.PathSeparator {
			relpath = relpath[1:]
		}
		post_list = append(post_list, relpath)
		return nil
	}
	if nil != filepath.WalkDir(env.source_dir, find_posts) {
		STDERR_LOG.Fatalf("Could not walk returned %v\n", env.source_dir)
	}


	var posts = make([]Post, 0, len(post_list))

	var wg sync.WaitGroup
	var has_error = false
	visit := func (path string, dir fs.DirEntry, err error) error {
		if has_error {
			// This does work without any sync primatives, it just takes a while
			return fmt.Errorf("Exit early due to error")
		}
		if dir.IsDir() {
			return nil
		}
		relpath, _ := strings.CutPrefix(path, env.templs_dir)
		if relpath[0] == os.PathSeparator {
			relpath = relpath[1:]
		}

		var langs []string
		has_lang := strings.Contains(relpath, "{{LANG}}")
		has_name := strings.Contains(relpath, "{{NAME}}")

		if has_lang {
			langs = LANG_LIST
		} else {
			langs = []string{""}
		}
		_ = langs

		if has_name {
			posts = posts[:0]
			dir := filepath.Dir(relpath)
			for _, post := range(post_list) {
				STDERR_LOG.Println("post", post)
				if (dir == filepath.Dir(post)) {
					base := filepath.Base(post)
					posts = append(posts, Post{
						base: post,
						stem: base[:len(base) - len(filepath.Ext(base))],
					})
				}
			}
			AssertLE(len(posts), len(post_list))
		} else {
			posts = []Post{Post{"",""}}
		}

		for _, lang := range(langs) {
			for _, post := range(posts) {
				var src_relpath string = post.base
				var out_relpath string = relpath
				if has_name {
					src_relpath = strings.ReplaceAll(src_relpath, "{{NAME}}", post.stem)
					out_relpath = strings.ReplaceAll(out_relpath, "{{NAME}}", post.stem)
				}

				if has_lang {
					out_relpath = strings.ReplaceAll(out_relpath, "{{LANG}}", lang)
				}
				out_stem := out_relpath[:len(out_relpath) - len(filepath.Ext(out_relpath))]

				wg.Add(1)
				go func() {
					defer wg.Done()
					if err := make_file(env, lang, relpath, src_relpath, out_stem); err != nil {
						// Because this is write-only, we do not need multi-threaded sync
						has_error = true
						STDERR_LOG.Printf("Failed to compile %q: %q -> %q\n   %v", relpath, src_relpath, out_stem, err)
					}
				}()
			}
		}

		return nil
	}

	if err := filepath.WalkDir(env.templs_dir, visit); err != nil {
		STDERR_LOG.Fatalf("Could not walk %q %v\n", env.templs_dir, err)
	}

	wg.Wait()
	if has_error {
		os.Exit(1)
	}
}


func AssertLE[T ~int](x, y T) {
	if (x <= y) {} else {
		STDERR_LOG.Fatalf("Not equal.\n  Expected: %v\n  Received: %v\n", x, y)
	}
}

func Must[T any](x T, err error) T {
	if err != nil {
		STDERR_LOG.Fatalln(err.Error())
	}
	return x
}

func find_git_root() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		fmt.Errorf("Could open: %v", err)
		os.Exit(1)
	}

	// Unlikely we wil be 100 folders in
	for i := 0; i < 100; i += 1 {
		_, err := os.Stat(filepath.Join(dir, "make.go"))
		if os.IsNotExist(err) {
			dir = filepath.Dir(dir)
		}else {
			return dir, nil
		}
	}
	return "", nil
}
