using Godot;
using System.Collections.Generic;

namespace Hollowbrook.Sim;

/// <summary>
/// The balance sweep: takes the crop and tool numbers the game already declares and
/// answers "how long does planting take to pay for the next tool tier", for every
/// crop choice at once.
///
/// <para>
/// Why this is the C# system and not GDScript: <c>docs/MULTI_LANGUAGE_ARCHITECTURE.md</c>
/// records the measurement that decided it. This is a deterministic parameter sweep —
/// <c>days x strategies x plots</c> inner steps, re-run whenever content changes and
/// on every run of the test suite. It is a nested loop with a sort of pending
/// harvests in the middle, which is the shape that does not cache or vectorise in an
/// interpreter. It is also the only kind of call this boundary should carry: the data
/// goes in as flat arrays in one call and a report comes back, so nothing is marshalled
/// per frame and no object graph crosses.
/// </para>
///
/// <para>
/// <b>This is a planning model, not the game.</b> It knows nothing about stamina,
/// rain, festivals, foraging or quests — it models planting, because planting is the
/// income this model can express honestly from the numbers on disk. The two-year
/// headless simulation is the thing that plays the real systems; this one answers
/// "is the crop table itself coherent", which a real playthrough cannot answer
/// because a player only ever exercises one strategy.
/// </para>
///
/// <para>
/// Every number in the report derives from the arrays handed in. Nothing here
/// hard-codes a crop, a price or a tool: adding a fortieth crop changes the answer
/// without touching this file, which is the "content is data" rule holding across a
/// language boundary.
/// </para>
/// </summary>
[GlobalClass]
public partial class BalanceSweep : Resource
{
	/// <summary>Which crop a strategy plants in a given season.</summary>
	public enum Strategy
	{
		/// <summary>Highest gold per in-ground day. The obvious "what should I plant".</summary>
		BestPerDay,

		/// <summary>Highest profit per harvest, ignoring how long it takes.</summary>
		BestMargin,

		/// <summary>Cheapest seed that still turns a profit. What a broke player plants.</summary>
		Cheapest,

		/// <summary>Worst profitable crop. The floor: if even this reaches the gates, nothing is grindy.</summary>
		WorstPerDay,
	}

	private struct Crop
	{
		public float SeedCost;
		public float SellPrice;
		public float YieldAvg;
		public int DaysToGrow;
		public int RegrowDays;
		public bool Regrows;
		public int SeasonMask;
	}

	private struct Harvest
	{
		public int Day;
		public int Crop;
	}

	private const int Seasons = 4;

	/// <summary>
	/// Runs the sweep.
	/// </summary>
	/// <param name="totalDays">Horizon in days. 224 is two years.</param>
	/// <param name="daysPerSeason">28 in the shipped calendar.</param>
	/// <param name="startGold">Wallet at the start of the run.</param>
	/// <param name="plotCount">How many soil tiles the player can actually work.</param>
	/// <param name="seedCost">What the store charges for one seed of each crop.</param>
	/// <param name="sellPrice">What one unit of produce sells for.</param>
	/// <param name="yieldAvg">Mean produce per harvest, (min + max) / 2.</param>
	/// <param name="daysToGrow">Days in the ground before the first harvest.</param>
	/// <param name="regrowDays">Days between harvests once a regrower has started.</param>
	/// <param name="regrows">0 or 1, whether the plant survives harvesting.</param>
	/// <param name="seasonMask">Bit <c>s</c> set means plantable in season <c>s</c>.</param>
	/// <param name="toolCosts">Ascending purchase prices of the tool tiers.</param>
	/// <returns>
	/// A report dictionary: one entry per strategy with its end gold, gross revenue,
	/// seed spend and the day it bought each tool tier (-1 if never), plus the
	/// cross-strategy spread the balance assertions read.
	/// </returns>
	public Godot.Collections.Dictionary Run(
		int totalDays,
		int daysPerSeason,
		int startGold,
		int plotCount,
		float[] seedCost,
		float[] sellPrice,
		float[] yieldAvg,
		int[] daysToGrow,
		int[] regrowDays,
		int[] regrows,
		int[] seasonMask,
		float[] toolCosts
	)
	{
		var report = new Godot.Collections.Dictionary();

		int cropCount = seedCost.Length;
		if (cropCount == 0 || totalDays <= 0 || daysPerSeason <= 0 || plotCount <= 0)
		{
			report["ok"] = false;
			report["reason"] = "empty sweep input";
			return report;
		}

		var crops = new Crop[cropCount];
		for (int i = 0; i < cropCount; i++)
		{
			crops[i] = new Crop
			{
				SeedCost = i < seedCost.Length ? seedCost[i] : 0f,
				SellPrice = i < sellPrice.Length ? sellPrice[i] : 0f,
				YieldAvg = i < yieldAvg.Length ? yieldAvg[i] : 1f,
				DaysToGrow = i < daysToGrow.Length ? System.Math.Max(1, daysToGrow[i]) : 1,
				RegrowDays = i < regrowDays.Length ? regrowDays[i] : 0,
				Regrows = i < regrows.Length && regrows[i] != 0,
				SeasonMask = i < seasonMask.Length ? seasonMask[i] : 0xF,
			};
		}

		var tools = new List<float>(toolCosts);
		tools.Sort();

		var strategies = new Godot.Collections.Array();
		int fastestTier2 = -1;
		int slowestTier2 = -1;

		foreach (Strategy strategy in System.Enum.GetValues(typeof(Strategy)))
		{
			var result = RunOne(strategy, crops, tools, totalDays, daysPerSeason, startGold, plotCount);
			strategies.Add(result);

			// The tier-2 gate is the one every strategy has to clear for progression
			// to be reachable by play rather than by luck. Tier 1 is the starter tool;
			// tier 3+ is post-first-winter content.
			int day = BuyDay(result, 1);
			if (day < 0)
			{
				continue;
			}
			if (fastestTier2 < 0 || day < fastestTier2)
			{
				fastestTier2 = day;
			}
			if (slowestTier2 < 0 || day > slowestTier2)
			{
				slowestTier2 = day;
			}
		}

		var costArray = new Godot.Collections.Array();
		foreach (float c in tools)
		{
			costArray.Add(c);
		}

		report["ok"] = true;
		report["days"] = totalDays;
		report["strategies"] = strategies;
		report["tool_costs"] = costArray;
		report["fastest_tier2_day"] = fastestTier2;
		report["slowest_tier2_day"] = slowestTier2;
		report["crop_count"] = cropCount;
		return report;
	}

	/// <summary>The day a given tool tier was bought, or -1.</summary>
	public static int BuyDay(Godot.Collections.Dictionary result, int tier)
	{
		if (result == null || !result.ContainsKey("tool_days"))
		{
			return -1;
		}
		var days = (Godot.Collections.Array)result["tool_days"];
		if (tier < 0 || tier >= days.Count)
		{
			return -1;
		}
		return days[tier].AsInt32();
	}

	/// <summary>End gold for one strategy, for assertions that read a single number.</summary>
	public static float EndGold(Godot.Collections.Dictionary result)
	{
		if (result == null || !result.ContainsKey("end_gold"))
		{
			return 0f;
		}
		return result["end_gold"].AsSingle();
	}

	private Godot.Collections.Dictionary RunOne(
		Strategy strategy,
		Crop[] crops,
		List<float> tools,
		int totalDays,
		int daysPerSeason,
		int startGold,
		int plotCount
	)
	{
		float gold = startGold;
		float gross = 0f;
		float seedSpend = 0f;
		int occupied = 0;

		var toolDays = new Godot.Collections.Array();
		for (int t = 0; t < tools.Count; t++)
		{
			toolDays.Add(-1f);
		}
		int nextTool = 0;

		var pending = new List<Harvest>();

		for (int day = 0; day < totalDays; day++)
		{
			int season = (day / daysPerSeason) % Seasons;
			int endOfSeason = ((day / daysPerSeason) + 1) * daysPerSeason - 1;

			// Everything ripe today pays out. Selling at the bin on the day it is
			// picked is the optimistic half of the model; the pessimistic half is
			// that planting is charged the moment the seed goes in the ground.
			for (int i = pending.Count - 1; i >= 0; i--)
			{
				if (pending[i].Day != day)
				{
					continue;
				}
				Harvest h = pending[i];
				pending.RemoveAt(i);
				Crop c = crops[h.Crop];
				float paid = c.SellPrice * c.YieldAvg;
				gold += paid;
				gross += paid;
				occupied--;

				if (c.Regrows && c.RegrowDays > 0 && day + c.RegrowDays <= endOfSeason)
				{
					pending.Add(new Harvest { Day = day + c.RegrowDays, Crop = h.Crop });
					occupied++;
				}
			}
			pending.Sort((a, b) => a.Day.CompareTo(b.Day));

			// Buy the next tier the moment it is affordable: gate timing is the whole
			// point of the sweep, and hoarding would measure the player, not the table.
			while (nextTool < tools.Count && gold >= tools[nextTool])
			{
				gold -= tools[nextTool];
				toolDays[nextTool] = day;
				nextTool++;
			}

			// Plant every free, affordable plot that will ripen before the season ends.
			int crop = Pick(crops, season, strategy);
			if (crop < 0)
			{
				continue;
			}
			while (occupied < plotCount
				&& gold >= crops[crop].SeedCost
				&& day + crops[crop].DaysToGrow <= endOfSeason)
			{
				gold -= crops[crop].SeedCost;
				seedSpend += crops[crop].SeedCost;
				pending.Add(new Harvest { Day = day + crops[crop].DaysToGrow, Crop = crop });
				occupied++;
			}
		}

		var result = new Godot.Collections.Dictionary
		{
			{ "id", strategy.ToString() },
			{ "label", Label(strategy) },
			{ "days", totalDays },
			{ "end_gold", gold },
			{ "gross", gross },
			{ "seed_spend", seedSpend },
			{ "net", gross - seedSpend },
			{ "tool_days", toolDays },
		};
		return result;
	}

	/// <summary>
	/// The crop this strategy plants in this season, or -1 for none.
	/// </summary>
	/// <remarks>
	/// Only ever a crop that is plantable this season and profitable after its seed.
	/// A strategy that deliberately lost money on a crop would report a bad gate
	/// timing for a reason no player could act on.
	/// </remarks>
	private static int Pick(Crop[] crops, int season, Strategy strategy)
	{
		int best = -1;
		float bestScore = 0f;

		for (int i = 0; i < crops.Length; i++)
		{
			Crop c = crops[i];
			if ((c.SeasonMask & (1 << season)) == 0)
			{
				continue;
			}
			float profit = c.SellPrice * c.YieldAvg - c.SeedCost;
			if (profit <= 0f)
			{
				continue;
			}
			float score = strategy switch
			{
				Strategy.BestPerDay => profit / c.DaysToGrow,
				Strategy.BestMargin => profit,
				Strategy.Cheapest => -c.SeedCost,
				_ => -profit / c.DaysToGrow,
			};

			if (best < 0 || IsBetter(score, strategy, bestScore))
			{
				best = i;
				bestScore = score;
			}
		}
		return best;
	}

	private static bool IsBetter(float score, Strategy strategy, float current)
	{
		return strategy switch
		{
			Strategy.BestPerDay or Strategy.BestMargin => score > current,
			_ => score < current,
		};
	}

	private static string Label(Strategy strategy)
	{
		return strategy switch
		{
			Strategy.BestPerDay => "Best gold per day",
			Strategy.BestMargin => "Best profit per harvest",
			Strategy.Cheapest => "Cheapest seed",
			Strategy.WorstPerDay => "Worst profitable crop",
			_ => strategy.ToString(),
		};
	}
}
