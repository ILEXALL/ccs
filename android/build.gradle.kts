allprojects {
    repositories {
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

/*
 * Force all Android modules, including Flutter plugins such as geocoding_android,
 * to compile with Android SDK 36. Some plugins set their own compileSdk later
 * in their Gradle files, so apply this after each subproject has been evaluated.
 */
subprojects {
    afterEvaluate {
        plugins.withId("com.android.application") {
            extensions.configure<com.android.build.api.dsl.ApplicationExtension>("android") {
                compileSdk = 36
            }
        }

        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                compileSdk = 36
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// App Check skips applying Kotlin on AGP 9, but this project explicitly opts
// out of AGP's built-in Kotlin. Compile the plugin's Kotlin sources explicitly.
subprojects {
    if (name == "firebase_app_check" &&
        providers.gradleProperty("android.builtInKotlin").orNull == "false") {
        plugins.withId("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}