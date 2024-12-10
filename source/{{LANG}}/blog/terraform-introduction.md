# Frontmatter
title: OpenTofu/Terraform Introduction
date:  2024-12-14
langs: en jp

`@*`

`# run: tetra parse % | cmark-gfm`


# Introduction: Why OpenTofu

I am this article primarily at those wishing to evaluate whether or not to include OpenTofu/Terraform in their tech stack and to newcomers who are curious.

OpenTofu is a fork of Terraform when HashiCorp changed its license from an open-source license (MPL-2.0) to a source-available license (BUSL 1.1).[^1]
It is an automation tool that reads text-file recipes to perform various [CRUD](https://en.wikipedia.org/wiki/Create%2C_read%2C_update_and_delete) actions.
In other words, you use to manage resources where creation/updating/deletion all require different types of actions.
It has become the poster child of DevOps and cloud infrastructure as the tool for provisioning (creating) infrastructure.

## Explanatory use case

I have a text file that lists 100+ GitHub repositories that I want to checkout on my local PC.
If I were to change a name in text file, I would this to be reflected in my local checkouts.

* Read: (skip) For this use case, a local file will the source of truth for the list of repositories, though we could have just as easily use GitHub as the source of truth.
* __Creation__: I would want to do a `git clone`
* __Update__: If the name changes, I would want to rename the directory
* __Deletion__: I would want remove the directory

A naive implementation just be a script that loops over a list of repo names with a parameter of create/update/delete that you pass in as the argument.
But, you quickly run into the issue of how do you know when to perform which action, when all you have is a text file that declares what the final state should be.
In other words, you need a record of what has been created (i.e. the tfstate) to know you: should create if is absent, update it if it changed, or delete it if it is present but absent from your input.

# What is OpenTofu

As in the explanatory use case, the day-to-day of using this tool is editing your input recipe HCL files and then running `tofu apply` or `terraform apply`, which runs API calls (providers) and creates the tfstate record of resources managed.
The following are the major concepts on the CLI level:

* __HCL__ (HashiCorp Configuration Language) and __tfvars__ files: these are your *.tf and *.tfvars files that together declare our final state. This is analogous the input file in our use case.
* __tfstate__: A JSON file that contains all the values as of the last apply
* __CLI__: The OpenTofu or Terraform executable is essential a parallel task runner. It compiles HCL + tfvars files into a dependency graph of what tasks, what depend on what, and runs it.
* __Providers__: Executables primarily written in Go that perform the API calls. These are called by the CLI under the same process and are communicated through the gRPC binary protocol.[^2]
* __tfstate lock__: A file that the CLI sets and unsets to indicate that someone is currently manipulating the tfstate. 
* __provider lock__: The terraform.lock file. This tracks the exact versions of your providers (like other package managers), especially relevant if you put constraints on them

## HCL concepts

A configuration language is combination of a data format and functions to express that data more easily, and is foremost a data and not foremost an meant to be executed.
The first job of the OpenTofu/Terraform CLI is to compile HashiCorp Configuration Language (HCL) to a dependency graph encoded as JSON (through `tofu validate` or `terraform validate`).[^3]
The second job of the OpenTofu/Terraform CLI is to perform the necessary CRUD effects as described by graph through the providers (through `tofu apply` or `terraform validate`).

Here is a implementation of the explanatory use case.

```hcl
variable "unused" { type = string }

locals {
  base_dir = ".."
  repos = {
    "core"     = "yueleshia/tetra"
    "markdown" = "yueleshia/tetra-markdown"
    "typst"    = "yueleshia/tetra-typst"
    "site"     = "yueleshia/site"
  }
}

#data "github_repository" "repo" {}  # This is a comment

resource "terraform_data" "repo" {
  for_each = local.repos:

  triggers_replace = each.value

  provisioner "local-exec" {
    command = <<-EOT
      dir="${base_dir}/${each.value}"
      [ -d "$dir" ] && { printf %s\\n "The path '${each.value}' already exists" >&2; exit 1; }
      mkdir "$dir" || exit "$?"
      git -C "$dir" init _bare || exit "$?"
      git -C "$dir/_bare" remote add origin "git@github.com:${each.value}.git" || exit "$?"
      git -C "$dir/_bare" config --local core.sshCommand "ssh -i ~/.ssh/github" || exit "$?"

      git -C "$dir/_bare" switch --create _bare
      git -C "$dir/_bare" fetch  --depth 1
      git -C "$dir/_bare" worktree add "../main" "origin/main" || exit "$?"
    EOT
  }

  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      [ -d "${self.triggers_replace}" ] && rm -r "${self.triggers_replace}"
    EOT
  }
}

output "unused" { value = "" }
```

At its core, there are just five important blocks in HCL:

* `variable`: your inputs
* `data`: intended to only perform CRUD reads.[^4]
* `resource`: has a full CRUD lifecycle. When writing Go providers, you typically will have to duplicate read function of data blocks.
* `locals`: the equivalent of variables in programming languages that promote code reuse by storing computations.
* `output`: your outputs, mostly used for modules or when reading [external tfstate](https://developer.hashicorp.com/terraform/language/state/remote-state-data)

HCL considers all `*.tf` files in a single directory.
To import HCL from another directory you have to use a `module` block.
`*.tfvars` files are one of the many ways to specify defaults for your variable blocks.

```hcl
module "any_name" {
  source = "./path-to-dir"

  var1 = ""
  var2 = false
}
```

# Bounds of OpenTofu/Terraform

## Not a good fit for managing local resources on remote machines

Providers

- [x] Local resources
- [x] Remote resources
- [ ] Local resources on Remote


## Semi-lazy evaluation, not full-lazy

HCL does compile to without knowing all values at compile time, (e.g. when you reuse results of data and resource outputs)
While terraform does a decent job of deferring evaluating of values

## Need for wrappers for full automation

## Not designed with code reuse from the ground up

## Security and the Registry

Running OpenTofu/Terraform download executables (providers) which are run on every `apply`.
You probably do not want to run unmoderated code on your PC.
HashiCorp and

# Further reading

* Catrill, Bryan. [Corporate Open Source Anti-Patterns: A Decade Later](https://www.youtube.com/watch?v=9QMGAtxUlAc) P99 Conf 2023, SycllaDB. 2023-10-19. https://www.youtube.com/watch?v=9QMGAtxUlAc .
* Parker-Shemilt, Tom. [PoC Terraform Provider in Rust](https://tevps.net/blog/2021/11/7/poc-terraform-provider-rust/). 2023-11-07. https://tevps.net/blog/2021/11/7/poc-terraform-provider-rust/
* [the following link](http://www.infrastructures.org/papers/turing/turing.html)

# References

[^1]: [HashiCorp adopts Business-Source License](https://www.hashicorp.com/blog/hashicorp-adopts-business-source-license)

[^2]: [How Terraform Works With Plugins](https://developer.hashicorp.com/terraform/plugin/how-terraform-works#terraform-plugin-protocol)

[^3]: Taking a look at [how terranix runs](https://terranix.org/documentation/getting-started.html), you can see that they use nix language (terranix) to generate a JSON dependency graph which is then read by the terraform CLI.

[^4]: One quirk of data blocks is that they are recorded in the tfstate. They are 
