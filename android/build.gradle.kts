allprojects {
    repositories {
        val mirror = java.util.Properties().apply {
            rootProject.file("../tool/gradle/kotlin-mirror.properties").inputStream().use { load(it) }
        }

        // Kotlin compiler downloads have hit GitHub HTTP 504 in CI.
        maven {
            url = uri(mirror.getProperty("url"))
            content { includeGroup(mirror.getProperty("group")) }
        }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
