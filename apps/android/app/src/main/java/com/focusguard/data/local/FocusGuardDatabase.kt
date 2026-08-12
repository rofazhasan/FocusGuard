package com.focusguard.data.local

import androidx.room.*
import java.util.UUID

@Entity(tableName = "policies")
data class PolicyEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val name: String,
    val limitSeconds: Int,
    val period: String = "DAILY",
    val scheduleCron: String? = null,
    val timezone: String = "UTC",
    val enforcementMode: String = "BLOCK",
    val isEnabled: Boolean = true,
    val version: Int = 1,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)

@Entity(
    tableName = "policy_targets",
    foreignKeys = [
        ForeignKey(
            entity = PolicyEntity::class,
            parentColumns = ["id"],
            childColumns = ["policyId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index(value = ["policyId"])]
)
data class PolicyTargetEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val policyId: String,
    val targetType: String, // APP, WEBSITE, CATEGORY
    val targetValue: String
)

@Entity(
    tableName = "usage_aggregates",
    indices = [Index(value = ["targetValue", "date"], unique = true)]
)
data class UsageAggregateEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val targetValue: String,
    val date: String, // YYYY-MM-DD
    val totalDurationSeconds: Int = 0
)

@Dao
interface PolicyDao {
    @Query("SELECT * FROM policies WHERE isEnabled = 1")
    suspend fun getEnabledPolicies(): List<PolicyEntity>

    @Query("SELECT * FROM policy_targets WHERE policyId = :policyId")
    suspend fun getTargetsForPolicy(policyId: String): List<PolicyTargetEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPolicy(policy: PolicyEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTargets(targets: List<PolicyTargetEntity>)
}

@Dao
interface UsageDao {
    @Query("SELECT SUM(totalDurationSeconds) FROM usage_aggregates WHERE targetValue = :targetValue AND date = :date")
    suspend fun getTotalDuration(targetValue: String, date: String): Int?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUsage(aggregate: UsageAggregateEntity)
}

@Database(
    entities = [PolicyEntity::class, PolicyTargetEntity::class, UsageAggregateEntity::class],
    version = 1,
    exportSchema = false
)
abstract class FocusGuardDatabase : RoomDatabase() {
    abstract fun policyDao(): PolicyDao
    abstract fun usageDao(): UsageDao
}
