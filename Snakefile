import os
import workflow.snakemake_tools as tools

rule all:
    group: "collate"
    input:
        summary = "results.json",
        website = "{}/website.complete.temp".format(tools.TEMPDIR),
    threads: 1
    resources:
        mem_mb = 1,
        disk_mb = 1

rule website:
    group: "collate"
    input: tools.datasets
    output: temp("{}/website.complete.temp".format(tools.TEMPDIR))
    threads: 1
    resources:
        mem_mb = 1,
        disk_mb = 1
    shell: "touch {output}"

rule docker:
    group: "docker"
    input: tools.push_images
    threads: 1
    resources:
        mem_mb = 1,
        disk_mb = 1

rule docker_build:
    group: "docker"
    input: tools.build_images
    threads: 1
    resources:
        mem_mb = 1,
        disk_mb = 1

rule docker_pull:
    group: "docker"
    input: tools.pull_images
    threads: 1
    resources:
        mem_mb = 1,
        disk_mb = 1

rule summary:
    group: "collate"
    input:
        script = "workflow/collate_all.py",
        methods = tools.all_methods,
    params:
        dir = tools.TEMPDIR
    output: "results.json"
    threads: 1
    resources:
        mem_mb = 100,
        disk_mb = 500
    shell: "python3 {input.script} {params.dir} {output}"

rule collate_dataset:
    group: "collate"
    input:
        script = "workflow/collate_dataset.py",
        methods = tools.methods,
    params:
        dir = tools.TEMPDIR
    output: "{}/{{task}}/{{dataset}}.json".format(tools.RESULTS_DIR)
    threads: 1
    resources:
        mem_mb = 100,
        disk_mb = 500
    shell:
        """python3 {input.script} {wildcards.task} {wildcards.dataset} \
        {params.dir}/{wildcards.task}/{wildcards.dataset} {output}"""

rule collate_method:
    group: "collate"
    input:
        script = "workflow/collate_method.py",
        meta = "{tempdir}/{task}/{dataset}/{method}.meta.json",
        metrics = tools.metrics,
    output: temp("{tempdir}/{task}/{dataset}/{method}.result.json")
    threads: 1
    resources:
        mem_mb = 100,
        disk_mb = 500
    shell:
        """python3 {input.script} {wildcards.task} {input.meta} \
        {wildcards.tempdir}/{wildcards.task}/{wildcards.dataset}/{wildcards.method} \
        {output}"""

rule evaluate_metric:
    group: "{task}_{dataset}_{method}_metrics"
    input:
        script = "workflow/evaluate_metric.py",
        data = "{tempdir}/{task}/{dataset}/{method}.method.h5ad",
    output: temp("{tempdir}/{task}/{dataset}/{method}/{metric}.metric.json")
    params:
        workdir = tools.DOCKER_DIR,
        docker = tools.docker_command
    threads: tools.N_THREADS
    resources:
        mem_mb = 1000,
        disk_mb = 32000
    shell:
        """{params.docker} {params.workdir} {input.script} {wildcards.task} \
        {wildcards.metric} {input.data} {output} && \
        docker stop $CONTAINER'"""

rule run_method:
    group: "{task}_{dataset}_methods"
    input:
        script = "workflow/run_method.py",
        data = "{tempdir}/{task}/{dataset}.data.h5ad",
    output:
        data = temp("{tempdir}/{task}/{dataset}/{method}.method.h5ad"),
        json = temp("{tempdir}/{task}/{dataset}/{method}.meta.json"),
    params:
        workdir = tools.DOCKER_DIR,
        docker = tools.docker_command
    threads: tools.N_THREADS
    resources:
        mem_mb = 1000,
        disk_mb = 32000
    shell:
        """{params.docker} {params.workdir} {input.script} {wildcards.task} \
        {wildcards.method} {input.data} {output.data} {output.json} && \
        docker stop $CONTAINER'"""

rule load_dataset:
    group: "{task}_datasets"
    input:
        script = "workflow/load_dataset.py",
        code = "openproblems/version.py",
    output: temp("{tempdir}/{task}/{dataset}.data.h5ad")
    params:
        workdir = tools.DOCKER_DIR,
        docker = tools.docker_command
    threads: tools.N_THREADS
    resources:
        mem_mb = 1000,
        disk_mb = 32000
    shell: """{params.docker} {params.workdir} {input.script} {wildcards.task} \
           {wildcards.dataset} {output} && \
           docker stop $CONTAINER'"""

rule build_docker:
    group: "docker"
    input:
        dockerfile = "docker/{image}/Dockerfile",
        requirements = tools.docker_requirements,
    output:
        "docker/{image}/.docker_build"
    params:
        user = "singlecellopenproblems"
    shell:
        """docker build -f {input.dockerfile} -t {params.user}/{wildcards.image} . \
        && touch {output}"""

rule password_docker:
    group: "docker"
    output:
        filename = temp(".docker_password")
    run:
        with open(output.filename, 'w') as handle:
            handle.write(tools.DOCKER_PASSWORD)

rule login_docker:
    group: "docker"
    input:
        ".docker_password"
    output:
        temp(".docker_login")
    shell:
        """docker login --username=singlecellopenproblems --password=$(cat {input}) && \
        touch {output}"""

rule push_docker:
    group: "docker"
    input:
        build = "docker/{image}/.docker_build",
        login = ".docker_login",
    output:
        "docker/{image}/.docker_push"
    shell:
        "docker push singlecellopenproblems/{wildcards.image} && date +%s > {output}"

rule pull_docker:
    group: "docker"
    output:
        temp("docker/{image}/.docker_pull")
    shell:
        "docker pull singlecellopenproblems/{wildcards.image} && touch {output}"
