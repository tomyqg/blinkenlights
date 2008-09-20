package de.blinkenlights.bmix.statistics;

import java.io.Serializable;
import java.util.List;

public interface StatisticsItem extends Serializable {

	public String getName();
	
	public String toHtml();
	
	/**
	 * Returns the unique identifier of the real object this
	 * statistics item reports on.
	 */
	public long getId();
}
