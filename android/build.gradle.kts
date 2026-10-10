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
// [플러그인 compileSdk 보정]
// flutter_reactive_ble 의 Android 구현(reactive_ble_mobile 5.5.0)은 compileSdk 33 으로 고정돼 있는데,
// 함께 끌려오는 androidx 라이브러리들은 34 이상을 요구해서 Android 빌드가 실패한다.
// (5.6.0 은 반대로 37 을 요구해 현재 Android Gradle Plugin 권장 최대치 36 을 넘는다.)
// 그래서 모든 Android 라이브러리 플러그인을 앱과 같은 36 으로 컴파일하도록 맞춘다.
// compileSdk 는 "어떤 API 로 컴파일하나"일 뿐 minSdk/targetSdk(실행 기기 범위·동작)는 바꾸지 않는다.
// 플러그인이 34 이상으로 업데이트되면 이 블록은 지워도 된다.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.let { android ->
            if ((android.compileSdk ?: 0) < 36) android.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
