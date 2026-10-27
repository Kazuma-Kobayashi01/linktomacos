plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

// 两个 App 共用的代码：连接、协议、增强服务、资源。没有界面，也不声明任何组件（组件各自在 :service / :app 的清单里）。
android {
    namespace = "com.linktomacos.android"
    compileSdk = 37

    defaultConfig {
        minSdk = 35
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(libs.androidx.core.ktx)
    api(libs.kotlinx.serialization.json)
    api(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.lifecycle.service)
    testImplementation(libs.junit)
}
